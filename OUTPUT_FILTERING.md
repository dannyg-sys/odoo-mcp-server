# Odoo MCP Server - Smart Output Filtering

## Overview
The Odoo MCP server now intelligently filters command output to save tokens while ensuring critical errors and warnings are never hidden.

## Behavior

### Default Mode (errorOnly = false)
**Shows:**
- ✅ All errors (syntax errors, import errors, exceptions, failures)
- ✅ All warnings (deprecation warnings, obsolete features)
- ✅ Module update confirmations
- ✅ Database migration messages
- ✅ Summary messages

**Hides:**
- ❌ Verbose logging (INFO level)
- ❌ Debug output
- ❌ Routine initialization messages
- ❌ SQL query logs
- ❌ Asset compilation details (unless errors)

**Token savings:** ~70-80% reduction in typical successful operations

### Error-Only Mode (errorOnly = true)
**Shows:**
- ✅ Critical errors only
- ✅ Exceptions and tracebacks
- ✅ Failed operations

**Hides:**
- ❌ All warnings
- ❌ Deprecation notices
- ❌ Routine confirmations

**Token savings:** ~90-95% reduction in typical successful operations

### What Gets Filtered

#### Always Included (Critical Patterns)
- `error`, `failed`, `exception`, `traceback`
- `ValueError`, `AttributeError`, `ImportError`, `SyntaxError`
- `could not`, `cannot`, `unable to`
- `modules updated`, `modules installed`, `module loaded`
- `database`, `migrating`, `init module`
- `server restarted`, `frontend updated`

#### Included Only in Default Mode
- `warning`, `deprecated`, `obsolete`

#### Always Filtered Out
- INFO level logs: `INFO`, `Loading`, `Generating`
- Debug output: `DEBUG`, detailed tracebacks without errors
- SQL queries and timing information
- Asset compilation progress (unless errors)
- Routine startup messages

## Examples

### Example 1: Successful Update (No Issues)
**Raw output (300+ lines):**
```
2024-12-04 INFO odoo: Loading module purchase_dual_unit
2024-12-04 INFO odoo.modules.loading: Loading 1 modules...
2024-12-04 INFO odoo.modules.loading: 1 modules loaded in 0.02s, 0 queries
... (298 more lines)
```

**Filtered output:**
```
✓ Operation completed successfully with no errors or warnings.
```

**Token savings: ~2,500 tokens → ~20 tokens**

### Example 2: Update with Warnings
**Raw output (450+ lines):**
```
2024-12-04 INFO odoo: Loading module nell_thai_qr
2024-12-04 WARNING odoo.modules.module: Module nell_thai_qr: deprecated method `_get_qr_code`
2024-12-04 INFO odoo.modules.loading: Loading 1 modules...
... (447 more lines)
```

**Filtered output:**
```
ℹ️ Warnings found (no errors):

2024-12-04 WARNING odoo.modules.module: Module nell_thai_qr: deprecated method `_get_qr_code`
```

**Token savings: ~3,500 tokens → ~50 tokens**

### Example 3: Update with Errors
**Raw output (600+ lines):**
```
2024-12-04 INFO odoo: Loading module nell_scb_qr_pos
2024-12-04 ERROR odoo.modules.module: Failed to load module nell_scb_qr_pos
2024-12-04 ERROR odoo.sql_db: bad query: INSERT INTO pos_payment_method
Traceback (most recent call last):
  File "/Users/dgoo2308/git/odoo18/odoo/odoo/modules/module.py", line 123
  ... (full traceback)
ValueError: Invalid field 'scb_qr_code' in model 'pos.payment.method'
... (590 more lines)
```

**Filtered output:**
```
⚠️ ERRORS FOUND - Review the details below:

2024-12-04 ERROR odoo.modules.module: Failed to load module nell_scb_qr_pos
2024-12-04 ERROR odoo.sql_db: bad query: INSERT INTO pos_payment_method
Traceback (most recent call last):
  File "/Users/dgoo2308/git/odoo18/odoo/odoo/modules/module.py", line 123
  ... (full traceback)
ValueError: Invalid field 'scb_qr_code' in model 'pos.payment.method'
```

**Token savings: ~4,500 tokens → ~200 tokens (all critical info preserved)**

## Command Usage

### Update Module (Default - Shows Warnings)
```typescript
await odoo_update_module({
  module: "nell_thai_qr",
  errorOnly: false  // Default
});
```

### Update Module (Error-Only - Suppress Warnings)
```typescript
await odoo_update_module({
  module: "nell_thai_qr",
  errorOnly: true
});
```

### Install Modules
```typescript
await odoo_install_modules({
  modules: "stock_account,purchase_stock",
  errorOnly: false  // Shows warnings
});
```

### Update Frontend
```typescript
await odoo_update_frontend({
  modules: "nell_thai_qr_pos",
  errorOnly: false  // Shows warnings
});
```

## Benefits

1. **Token Efficiency**: Save 70-95% of tokens on routine operations
2. **Never Miss Errors**: All critical information is always preserved
3. **Configurable**: Use `errorOnly: true` for even more aggressive filtering
4. **Clear Summaries**: Success/warning/error status at a glance
5. **Full Details When Needed**: Complete error traces and context preserved

## Migration from Previous Version

**No breaking changes!** The API remains identical:
- All tools work exactly the same
- The `errorOnly` parameter works as before
- Only the output verbosity has changed (for the better)

## When to Use Full Output

If you need complete verbose logs for debugging:
1. Use `odoo_get_logs` tool to read the full `odoo.log` file
2. The complete unfiltered output is always available in the log file
3. The filtering only affects MCP tool responses, not the actual logs

## Technical Details

The filtering is performed by the `filterOdooOutput()` method which:
1. Scans each line for critical patterns (errors, warnings, confirmations)
2. Includes relevant context around errors
3. Excludes routine INFO/DEBUG logging
4. Preserves complete error tracebacks
5. Adds helpful summary headers

This ensures maximum token efficiency while maintaining full visibility of actual problems.
