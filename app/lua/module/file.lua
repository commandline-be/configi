--- File operations.
-- @module file
-- @author Eduardo Tongson <propolice@gmail.com>
-- @license MIT <http://opensource.org/licenses/MIT>
-- @added 0.9.0

local ENV, M, file = {}, {}, {}
local tostring, os, string = tostring, os, string
local cfg = require"configi"
local lib = require"lib"
local cmd = lib.cmd
local stat = require"posix.sys.stat"
local unistd = require"posix.unistd"
local pwd = require"posix.pwd"
local grp = require"posix.grp"
_ENV = ENV

M.required = { "path" }
M.alias = {}
M.alias.path = { "name", "link", "dest", "target" }
M.alias.src = { "source" }
M.alias.owner = { "uid" }
M.alias.group = { "gid" }

local owner = function(F, P, R)
    local report = {
        file_owner_ok = "file.owner: Owner/uid corrected.",
        file_owner_skip = "file.owner: Owner/uid already matches ",
        file_owner_fail = "file.owner: Error setting owner/uid."
    }
    local stat = stat.stat(P.path)
    local u = pwd.getpwuid(stat.st_uid)
    local uid = string.format("%s(%s)", u.pw_uid, u.pw_name)
    if P.owner == u.pw_name or P.owner == tostring(u.pw_uid) then
        return F.result(P.path, nil, report.file_owner_skip .. uid .. ".")
    end
    local args = { "-h", P.owner, P.path }
    lib.insert_if(P.recurse, args, 2, "-R")
    if F.run(cmd.chown, args) then
        return F.result(P.path, true, report.file_owner_ok)
    else
        return F.result(P.path, false, report.file_owner_fail)
    end
end

local group = function(F, P, R)
    local report = {
        file_group_ok = "file.group: Group/gid corrected.",
        file_group_skip = "file.group: Group/gid already matches ",
        file_group_fail = "file.group: Error setting group/gid."
    }
    local info = stat.stat(P.path)
    local g = grp.getgrgid(info.st_gid)
    local cg = string.format("%s(%s)", g.gr_gid, g.gr_name)
    if P.group == g.gr_name or P.group == tostring(g.gr_gid) then
        return F.result(P.path, nil, report.file_group_skip .. cg .. ".")
    end
    local args = { "-h", ":" .. P.group, P.path }
    lib.insert_if(P.recurse, args, 2, "-R")
    if F.run(cmd.chown, args) then
        return F.result(P.path, true, report.file_group_ok)
    else
        return F.result(P.path, false, report.file_group_fail)
    end
end

local mode = function(F, P, R)
    local report = {
        file_mode_ok = "file.mode: Mode corrected.",
        file_mode_skip = "file.mode: Mode matched.",
        file_mode_fail = "file.mode: Error setting mode."
    }
    local info = stat.stat(P.path)
    local mode = string.sub(tostring(string.format("%o", info.st_mode)), -3, -1)
    if mode == string.sub(P.mode, -3, -1) then
        return F.result(P.path, nil, report.file_mode_skip)
    end
    local args = { P.mode, P.path }
    lib.insert_if(P.recurse, args, 1, "-R")
    if F.run(cmd.chmod, args) then
        return F.result(P.path, true, report.file_mode_ok)
    else
        return F.result(P.path, false, report.file_mode_fail)
    end
end

local attrib = function(F, P, R)
    if not (P.owner or P.group or P.mode) then
        R.notify = P.notify
        R.repaired = true
        return R
    end
    if P.owner then
        R = owner(F, P, R)
    end
    if P.group then
        R = group(F, P, R)
    end
    if P.mode then
        R = mode (F, P, R)
    end
    return R
end

--- Set path attributes such as the mode, owner or group.
-- @param path path to modify [REQUIRED]
-- @param mode set the file mode bits
-- @param owner set the uid/owner [ALIAS: uid]
-- @param group set the gid/group [ALIAS: gid]
-- @usage file.attributes {
--   path = "/etc/shadow"
--   mode = "0600"
--   owner = "root"
--   group = "root"
-- }
function file.attributes(B)
    M.parameters = { "mode", "owner", "group" }
    local F, P, R = cfg.init(B, M)
    if not P.test and not stat.stat(P.path) then
        return F.result(P.path, false, "Missing path.")
    end
    return attrib(F, P, R)
end

--- Create a symlink.
-- @param src path where the symlink points to [REQUIRED]
-- @param path the symlink [REQUIRED] [ALIAS: link]
-- @param force remove existing symlink [CHOICES: "yes","no"]
-- @usage file.link {
--   src = "/"
--   path = "/home/ed/root"
-- }
function file.link(B)
    M.parameters = { "src", "force", "owner", "group", "mode" }
    M.report = {
        repaired = "file.link: Symlink created.",
            kept = "file.link: Already a symlink.",
          failed = "file.link: Error creating symlink."
    }
    local F, P, R = cfg.init(B, M)
    local symlink = unistd.readlink(P.path)
    if symlink == P.src then
        F.msg(P.src, G.kept, nil)
        return attrib(F, P, R)
    end
    local args = { "-s", P.src, P.path }
    lib.insert_if(P.force, args, 2, "-f")
    if F.run(cmd.ln, args) then
        F.msg(P.path, M.report.repaired, true)
        return attrib(F, P, R)
    else
        return F.result(P.path, false)
    end
end

--- Create a hard link.
-- @param src path where the hard link points to [REQUIRED]
-- @param path the hard link [REQUIRED] [ALIAS: link]
-- @param force remove existing hard link [CHOICES: "yes","no"]
-- @usage file.hard [[
--   src "/"
--   path "/home/ed/root"
-- ]]
function file.hard(B)
    M.parameters = { "src", "force", "owner", "group", "mode" }
    M.report = {
        repaired = "file.hard: Hardlink created.",
            kept = "file.hard: Already a hardlink.",
          failed = "file.hard: Error creating hardlink."
    }
    local F, P, R = cfg.init(B, M)
    local source = stat.stat(P.src)
    local link = stat.stat(P.path) or nil
    if not source then
        return F.result(P.path, false, string.format(" '%s' is missing", source))
    end
    if source and link and (source.st_ino == link.st_ino) then
        F.msg(P.path, M.report.kept, nil)
        return attrib(F, P, R)
    end
    local args = { P.src, P.path }
    lib.insert_if(P.force, args, 1, "-f")
    if F.run(cmd.ln, args) then
        F.msg(P.path, M.report.repaired, true)
        return attrib(F, P, R)
    else
        return F.result(P.path, false)
    end
end

--- Create a directory.
-- @param path path of the directory [REQUIRED]
-- @param mode set the file mode bits
-- @param owner set the uid/owner [ALIAS: uid]
-- @param group set the gid/group [ALIAS: gid]
-- @param force remove existing path before creating directory [CHOICES: "yes","no"] [DEFAULT: "no"]
-- @param backup rename existing path and prepend '._configi_' to the name [CHOICES: "yes","no"] [DEFAULT: "no"]
-- @usage file.directory {
--   path = "/usr/portage"
-- }
function file.directory(B)
    M.parameters = { "mode", "owner", "group", "force", "backup" }
    M.report = {
        repaired = "file.directory: Directory created.",
            kept = "file.directory: Already a directory.",
          failed = "file.directory: Error creating directory."
    }
    local F, P, R = cfg.init(B, M)
    local info = stat.stat(P.path)
    if info and (stat.S_ISDIR(info.st_mode) ~= 0 )then
        F.msg(P.path, M.report.kept, nil)
        return attrib(F, P, R)
    end
    if P.force then
        if P.backup then
            local dir, file = lib.split_path(P.path)
            F.run(os.rename, P.path, dir .. "/._configi_" .. file)
        end
        F.run(cmd.rm, { "-r", "-f", P.path })
    end
    if F.run(cmd.mkdir, { "-p", P.path }) then
        F.msg(P.path, M.report.repaired, true)
        return attrib(F, P, R)
    else
        return F.result(P.path, false)
    end
end

--- Touch a path.
-- @param path path to 'touch' [REQUIRED]
-- @param mode set the file mode bits
-- @param owner set the uid/owner [ALIAS: uid]
-- @param group set the gid/group [ALIAS: gid]
-- @usage file.touch {
--   path = "/srv/.keep"
-- }
function file.touch(B)
    M.parameters = { "mode", "owner", "group" }
    M.report = {
        repaired = "file.touch: touch(1) succeeded.",
          failed = "file.touch: touch(1) failed."
    }
    local F, P, R = cfg.init(B, M)
    if F.run(cmd.touch, { P.path }) then
        F.msg(P.path, M.report.repaired, true)
        return attrib(F, P, R)
    else
        return F.result(P.path, false)
    end
end

--- Remove a path.
-- @param path path to delete [REQUIRED]
-- @usage file.absent {
--   path = "/home/ed/.xinitrc"
-- }
function file.absent(B)
    M.report = {
        repaired = "file.absent: Successfully removed.",
            kept = "file.absent: Already absent.",
          failed = "file.absent: Error removing path.",
    }
    local F, P, R = cfg.init(B, M)
    if not stat.stat(P.path) then
        return F.kept(P.path)
    end
    return F.result(P.path, F.run(cmd.rm, { "-r", "-f", P.path }))
end

--- Copy a path.
-- @param path destination path [REQUIRED] [ALIAS: dest,target]
-- @param src source path to copy [REQUIRED]
-- @param recurse recursively copy source [CHOICES: "yes","no"] [DEFAULT: "no"]
-- @param force remove existing destination before copying [CHOICES: "yes","no"] [DEFAULT: "no"]
-- @param backup rename existing path and prepend '._configi_' to the name [CHOICES: "yes","no"] [DEFAULT: "no"]
-- @usage file.copy {
--   src = "/home/ed"
--   dest = "/mnt/backups"
-- ]]
function file.copy(B)
    M.parameters = { "src", "path", "recurse", "force", "backup" }
    M.report = {
        repaired = "file.copy: Copy succeeded.",
            kept = "file.copy: Not copying over destination.",
          failed = "file.copy: Error copying."
    }
    local F, P, R = cfg.init(B, M)
    local dir, file = lib.split_path(P.path)
    local backup = dir .. "/._configi_" .. file
    local present = stat.stat(P.path)
    if present and P.backup and (not stat.stat(backup)) then
        if not F.run(cmd.mv, { P.path, backup }) then
            return F.result(P.path, false)
        end
    elseif not P.force and present then
        return F.kept(P.path)
    end
    local args = { "-P", P.src, P.path }
    lib.insert_if(P.recurse, args, 2, "-R")
    lib.insert_if(P.force, args, 2, "-f")
    if F.run(cmd.cp, args) then
        return F.result(P.path, true)
    else
        F.run(cmd.rm, { "-r", "-f", P.path }) -- clean up incomplete copy
        return F.result(P.path, false)
    end
end

return file