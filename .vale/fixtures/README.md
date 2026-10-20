# Vale fixtures

Each `bad-*.md` file triggers exactly one project rule. Each `good-*.md`
file is its twin and triggers none. Run a fixture with the strict config:

```sh
vale --config .vale/strict.ini .vale/fixtures/bad-simply.md   # exits 1
vale --config .vale/strict.ini .vale/fixtures/good-simply.md  # exits 0
```
