# ACF via WP-CLI

Advanced Custom Fields (ACF / ACF Pro) is deceptive: field values look like ordinary post meta, but updating them via `wp post meta update` often breaks `get_field()` silently. This file explains why and how to update ACF values safely.

## The biggest gotcha: dual-row storage

For every ACF field value on a post, ACF writes **two** rows into `wp_postmeta`:

| Key | Value |
|-----|-------|
| `my_field` | The actual value |
| `_my_field` | `field_abc123` (the field definition's key) |

The underscore-prefixed row is a **reference** to the field definition. `get_field()` uses it to look up the field's type, choices, return format, and update filters. Without it:

- `format_value` doesn't run (image fields return attachment IDs instead of arrays; post-object fields return IDs instead of WP_Post; relationship fields return serialized IDs instead of hydrated objects)
- `acf_maybe_get_field()` falls back to a name-based lookup that works for simple fields on posts where the field group is registered, but **fails silently** for sub-fields, option pages, cloned fields, and name collisions

**Consequence**: `wp post meta update 42 hero_title 'New'` writes only the value row. `get_field('hero_title', 42)` may now return `null` or raw unformatted data.

**Fix**: use ACF's own API, which writes both rows and runs filters.

---

## Safe update: `wp eval` and `wp eval-file`

### Single value

```bash
wp eval "update_field('field_abc123', 'New title', 42);"
```

Pass the **field key** (`field_abc123`) when the target post has no existing value — required so the reference row gets the correct key. If the post already has a saved value, you can pass the field name (`hero_title`) and ACF will resolve it via the existing reference row.

Rule of thumb: when in doubt, pass the field key. You can find keys with:

```bash
wp eval "var_dump(acf_get_field_groups());"
# or for a specific group
wp eval "var_dump(acf_get_fields('group_xyz789'));"
```

### Batch updates via `eval-file`

Write a PHP script, execute it:

```php
<?php
// update-prism-rows.php
$updates = [
    123 => ['hero_title' => 'New title', 'partner_count' => 12],
    456 => ['hero_title' => 'Other'],
];
foreach ($updates as $post_id => $fields) {
    foreach ($fields as $selector => $value) {
        $ok = update_field($selector, $value, $post_id);
        WP_CLI::log(sprintf('post %d / %s => %s', $post_id, $selector, var_export($ok, true)));
    }
    clean_post_cache($post_id);
}
acf_flush_value_cache();
```

```bash
wp eval-file update-prism-rows.php
```

Why this over raw meta updates:
- `update_field()` writes both the value row and the field-key reference row
- Triggers `acf/update_value` filters (image URL→ID resolution, relationship serialization, etc.)
- Returns `false` when the new value equals the existing value — **not** an error, just a no-op per ACF docs

### Inspecting current state

```bash
# See both rows for one field
wp post meta list 42 --keys=hero_title,_hero_title

# Get the resolved, formatted value
wp eval "var_dump(get_field('hero_title', 42));"

# Raw DB value
wp eval "var_dump(get_post_meta(42, 'hero_title', true));"
```

Compare `get_field()` and `get_post_meta()` output — when they disagree, you're seeing a formatter issue or a missing reference row.

---

## Repeater fields

Storage layout (confirmed in ACF Pro source):

```
items                 "3"           ← row count (as string)
_items                "field_abc"   ← field key reference
items_0_title         "Hello"
_items_0_title        "field_xyz"   ← sub-field key reference
items_0_body          "..."
_items_0_body         "field_uvw"
items_1_title         "World"
_items_1_title        "field_xyz"
...
```

Three moving parts per row: top-level count, indexed value rows, indexed key-reference rows. **Do not hand-edit with `wp post meta update`.** Pitfalls:

- Forget to update the top-level count → ACF renders only N rows, extras are invisible
- Skip the `_items_0_title` reference rows → `format_value` doesn't run
- Shrink the count without deleting the abandoned sub-rows → orphan data

Use `update_field()` with an array of rows, or `update_sub_field()` for individual sub-field updates within a row (**1-based** row index, not 0-based):

```php
// Replace entire repeater
update_field('items', [
    ['title' => 'First', 'body' => 'Alpha'],
    ['title' => 'Second', 'body' => 'Beta'],
], $post_id);

// Update one sub-field in one row (note: 1-based index!)
update_sub_field(['items', 1, 'title'], 'Updated first row', $post_id);
```

For adding/removing rows: `add_row()`, `delete_row()`, `update_row()` — all in the ACF API. These handle the count + reference rows correctly.

---

## Flexible content

Same repeater pattern but sub-fields are keyed by **layout name**:

```
mysections                 a:2:{i:0;s:4:"hero";i:1;s:6:"banner";}   ← serialized array of layout names
_mysections                "field_abc"
mysections_0_hero_headline "..."
_mysections_0_hero_headline "field_xyz"
mysections_1_banner_image  "42"
_mysections_1_banner_image "field_uvw"
```

Layout changes (replacing a row's layout without changing the row index) leave orphan sub-rows if done via raw meta — ACF's `update_value` deletes them. Use `update_field()`.

`acfcloneindex` appears only in admin JS as a placeholder for newly-added rows — it should never appear in DB writes. If you see it, your payload was stale.

---

## Relationship / Post Object / Taxonomy / User fields

- **Multi-select** (`'multiple' => 1`): stored as a PHP-serialized array of integer IDs
- **Single-select Post Object / User**: scalar integer (as string in DB)
- **Relationship**: always an array, even with one selection
- **Taxonomy**: array of term IDs (not term objects)

`search-replace` implications:
- Plain URL replacements are safe (these fields don't store URLs; they store IDs)
- Integer ID remapping (`wp search-replace '42' '99'` on full tables) is **dangerous** — it can corrupt serialized-array length prefixes on unrelated rows. Always remap IDs with `update_field()` loops instead.

---

## Options pages

Options-page fields are stored in **`wp_options`**, not postmeta. This catches people.

Key format: `{options_id}_{field_name}` for the value row, `_{options_id}_{field_name}` for the field-key reference. `options_id` is typically `options` unless you set a custom ID in `acf_add_options_page()`.

```bash
# Read an options-page field
wp eval "var_dump(get_field('site_tagline', 'option'));"

# Raw value row
wp option get options_site_tagline

# Field key reference
wp option get _options_site_tagline

# Update
wp eval "update_field('site_tagline', 'New tagline', 'option');"
```

`wp post meta update` will NOT work for options-page fields because they're not in postmeta.

---

## `search-replace` across ACF content

URL migrations (dev → prod, staging → prod):

```bash
wp search-replace 'https://staging.example' 'https://prod.example' \
    --all-tables-with-prefix \
    --precise \
    --skip-columns=guid
```

ACF stores image/file values as **attachment IDs**, not URLs — URLs in ACF output come from the formatter looking up the attachment. So URL replacements usually don't need to touch ACF data itself; they only matter for post content and `wp_options` (siteurl, home, etc.).

**Exception**: the "URL" field type stores literal URLs. Those will be replaced.

**Don't** use `search-replace` to remap ACF's `field_xxx` keys. If you need to regenerate keys, re-save each post in admin (or via `update_field()` loop) rather than trying to rewrite the DB.

---

## Cleanup: orphan rows after re-scoping a field group

When a field group's `location` rule matches broadly (e.g. `post_type == page` for a group meant only for a specific template), every page edit screen writes an empty postmeta marker — at minimum the `_<field>` reference row pointing at the field key, even if the editor never touched the field. Tighten the rule (`page_template == ...` or `page == <id>`) and you're left with orphan rows on every post the old rule once matched.

Orphans are visually harmless (the field no longer renders — its location doesn't match), but they're noise and they accumulate.

### Survey first

Join `wp_postmeta` to `wp_posts` so you see which post **type** each row lives on — pure `wp post meta list` hides revisions:

```sql
SELECT pm.post_id, pm.meta_key, p.post_type, p.post_status, p.post_title
FROM wp_postmeta pm
JOIN wp_posts p ON p.ID = pm.post_id
WHERE pm.meta_key IN ('my_field', '_my_field');
```

Cross-reference against the posts the new `location` rule legitimately matches. Anything else is an orphan.

### `delete_post_meta()` skips revisions

This is the gotcha. `delete_post_meta($id, $key)` and `delete_field($key, $id)` route revision IDs (`post_type = revision`, `post_status = inherit`) to the parent post, leaving the revision's own postmeta row untouched. The call returns truthy with no error, then the orphan still appears on the next survey.

For revision rows, drop to direct SQL:

```php
global $wpdb;
$wpdb->delete($wpdb->postmeta, ['post_id' => $rev_id, 'meta_key' => $key]);
$wpdb->delete($wpdb->postmeta, ['post_id' => $rev_id, 'meta_key' => "_$key"]);
```

`$wpdb->delete` operates on the literal row regardless of post type. Use it for any revision-targeted postmeta cleanup, not just ACF.

### Belt and braces

Re-run the survey query after the sweep. Count of non-legitimate rows should be zero. Snapshot the DB before destructive cleanup on staging or above (see `safety.md`).

---

## Common symptoms and fixes

| Symptom | Cause | Fix |
|---------|-------|-----|
| `get_field()` returns empty after update | Missing `_fieldname` reference row | Use `update_field()` not `wp post meta update` |
| Old value keeps coming back | ACF's in-memory value cache; or persistent object cache holding stale field definitions | `acf_flush_value_cache()` + `wp cache flush` |
| "Field key missing" | Local JSON / PHP field group has different key than DB | Re-save post in admin, or `update_field()` with new key |
| Repeater shows fewer rows than expected | Top-level count meta not incremented | Use `update_field()` which handles count |
| Flex content layout renders blank | Layout name not in top-level serialized array | Update via `update_field()` |
| Image field returns int instead of array | Return format is "Array" but `format_value` skipped (missing ref row) | Use `update_field()` |
| `update_field()` returned false | New value equals existing — no-op per ACF docs | Not an error; verify with `get_field()` |
| Options-page field won't update via `wp post meta update` | Wrong table — lives in `wp_options` | `update_field('name', $v, 'option')` |

---

## Field-group definitions (the other thing `wp acf` *might* manage)

ACF Pro itself ships **no** `wp acf` CLI subcommands for field values. The community package `hoppinger/advanced-custom-fields-wpcli` adds `wp acf export|import|clean|status` for syncing field-group **definitions** (the JSON in `acf-json/`), but does NOT touch field values on posts. Adopt it only if useful for your workflow; pin to a commit SHA.

For this project, field groups are registered in PHP via `acf_add_local_field_group()` — they're code, not DB data. No CLI sync needed.

---

## Quick command recipes

```bash
# Inspect both rows for a field
wp post meta list 42 --keys=hero_title,_hero_title

# Update one value (simple)
wp eval "update_field('field_abc123', 'new value', 42);"

# Update an options-page field
wp eval "update_field('site_tagline', 'new', 'option');"

# Update a sub-field in a repeater (1-based index)
wp eval "update_sub_field(['items', 1, 'title'], 'updated', 42);"

# Dump all ACF field-group definitions
wp eval "var_dump(acf_get_field_groups());"

# List fields in a specific group
wp eval "var_dump(acf_get_fields('group_xyz789'));"

# Get a field's key by name (requires the group to be registered)
wp eval "echo acf_maybe_get_field('hero_title', 42)['key'];"
```
