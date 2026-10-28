-- Run with: nvim --headless -u NONE -i NONE -l tests/path.lua
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- These synchronous path tests do not need blink.lib's asynchronous filesystem helpers.
package.preload['blink.lib'] = package.preload['blink.lib'] or function() return {} end

local source = require('blink.cmp.sources.path')
local lib = require('blink.cmp.sources.path.lib')
local root = vim.fn.tempname()
vim.fn.mkdir(root .. '/buffer', 'p')
vim.fn.mkdir(root .. '/command', 'p')
root = vim.uv.fs_realpath(root)
vim.cmd.cd(root .. '/command')

local disabled = source.new({ get_cwd = function() return root .. '/buffer' end }).opts
local enabled = source.new({ get_cwd = disabled.get_cwd, enable_bare_relative_paths = true }).opts
assert(disabled.enable_bare_relative_paths == false, 'Bare relative paths must remain opt-in')

local function context(line, col, mode)
  col = col or #line
  local word = line:sub(1, col):match('[%w_]+$') or ''
  return {
    line = line,
    pos = { row = 0, col = col },
    cursor = { 1, col },
    mode = mode or 'default',
    bounds = { start_col = col - #word + 1, length = #word },
  }
end

for _, path in ipairs({ 'src/', 'src/file', 'a/b/c', '.config/nvim/file', 'my-dir/sub_dir/file', '目录/文件' }) do
  if path ~= '目录/文件' then
    assert(lib.dirname(disabled, context(path)) == nil, 'Disabled option accepted ' .. path)
  end
  local parent = assert(path:match('^(.*)/'))
  assert(lib.dirname(enabled, context(path)) == vim.fn.resolve(root .. '/buffer/' .. parent), path)
end

for _, line in ipairs({ 'local file = "a/b/c', "path='a/b/c", 'open(a/b/c', 'a/b/c-d' }) do
  assert(lib.dirname(enabled, context(line)) == root .. '/buffer/a/b', line)
end
assert(lib.dirname(enabled, context('edit a/b/c', nil, 'cmdline')) == root .. '/command/a/b')

vim.env.BLINK_PATH_TEST_ROOT = root .. '/buffer'
for _, line in ipairs({
  './src/file',
  '../src/file',
  root .. '/buffer/file',
  '~/src/file',
  '$BLINK_PATH_TEST_ROOT/src/file',
  '${BLINK_PATH_TEST_ROOT}/src/file',
  'https://example.com/src/file',
  'file:///src/file',
  '</src/file',
  'value / 3',
  'ordinary_word',
}) do
  assert(lib.dirname(enabled, context(line)) == lib.dirname(disabled, context(line)), line)
end

local ctx = context('"a/b/c/rest"', 6)
local ranges = lib.get_text_edit_ranges(ctx)
assert(ranges.file.start.character == 5 and ranges.file['end'].character == 6)
assert(ranges.directory.start.character == 5 and ranges.directory['end'].character == 7)
local item = lib.entry_to_completion_item(
  { name = 'completed', type = 'directory' },
  root .. '/buffer/a/b',
  ranges.directory,
  enabled
)
assert(item.textEdit.newText == 'completed/')
local text = ctx.line:sub(1, item.textEdit.range.start.character)
  .. item.textEdit.newText
  .. ctx.line:sub(item.textEdit.range['end'].character + 1)
assert(text == '"a/b/completed/rest"', 'Completion must preserve the parent path and suffix')

print('PASS opt-in bare paths, nested/quoted/Unicode paths, command cwd, existing prefixes, exclusions and text edits')
