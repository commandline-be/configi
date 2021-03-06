--- The `configure; make; make install` sequence.
-- @module make
-- @author Eduardo Tongson <propolice@gmail.com>
-- @license MIT <http://opensource.org/licenses/MIT>
-- @added 0.9.7

local M, make = {}, {}
local table = table
local cfg = require"cfg-core.lib"
local stat = require"posix.sys.stat"
local lib = require"lib"
local string = lib.string
local cmd = lib.exec.cmd
_ENV = nil

M.required = { "directory" }
M.alias = {}
M.alias.configure = { "options" }
M.alias.directory = { "dir", "build" }
M.alias.make = { "defines" }
M.alias.environment = { "env" }

--- Install a program via the `configure; make; make install` sequence of commands.
-- @Promiser path to directory containing the root of the configure script
-- @param configure options to pass to `./configure` [ALIAS: options]
-- @param make usually DEFINES that it passed to `make` [ALIAS: defines]
-- @param installs path of installed executable. Considered kept if it exists [ALIAS: creates]
-- @param environment space delimited string that contains environment passed to `./configure` and `make` [ALIAS: env]
-- @usage make.install"/home/ed/Downloads/something-1.0.0"{
--   make = "-DNDEBUG"
-- }
function make.install(S)
  M.parameters = { "configure", "make", "environment" }
  M.report = {
    repaired = "make.install: Successfully installed.",
    kept = "make.install: Already installed.",
    failed = "make.install: Error installing."
  }
  return function(P)
    P.directory = S
    local F, R = cfg.init(P, M)
    if R.kept then
      return F.kept(P.directory)
    end
    if P.environment then
      P.environment = string.to_array(P.environment)
    end
    local args, result
    if stat.stat(P.directory .. "/configure") then
      if P.configure then
        args = { env = P.environment, _cwd = P.directory }
        table.insert_if(P.configure, args, 1, string.to_array(P.configure))
        result = F.run(cmd["./configure"], args)
      else
        result = F.run(cmd["./configure"], { env = P.environment, cwd = P.directory })
      end
      if not result then
        return F.result(P.directory, nil, "`./configure` step failed")
      end
    end
    if P.make then
      args = { env = P.environment, cwd = P.directory }
      table.insert_if(P.make, args, 1, string.to_array(P.make))
      result = F.run(cmd.make, args)
    else
      result = F.run(cmd.make, { env = P.environment, cwd = P.directory })
    end
    if not result then
      return F.result(P.directory, nil, "`make` step failed")
    end
    if P.make then
      args = { env = P.environment, cwd = P.directory }
      table.insert(args, 1, "install")
      table.insert_if(P.make, args, 1, string.to_array(P.make))
      result = F.run(cmd.make, args)
    else
      result = F.run(cmd.make, { "install",  env = P.environment, cwd = P.directory })
    end
    if not result then
      return F.result(P.directory, nil, "`make install` step failed")
    end
    return F.result(P.directory, true)
  end
end

return make
