local common = require("spec.helpers.common")

describe("ada_ls.project_view.nodes", function()
  local nodes

  before_each(function()
    common.cleanup_packages()
    common.setup_vim_globals()
    nodes = require("ada_ls.project_view.nodes")
  end)

  after_each(function()
    common.cleanup_packages()
  end)

  describe("group_sources_by_dir", function()
    it("groups sources and returns sorted directories", function()
      local sources = {
        { directory = "/zeta", simple_name = "z.adb" },
        { directory = "/alpha", simple_name = "a.ads" },
        { directory = "/alpha", simple_name = "a.adb" },
      }

      local dirs, sorted = nodes.group_sources_by_dir(sources)

      assert.equals(2, #sorted)
      assert.equals("/alpha", sorted[1])
      assert.equals("/zeta", sorted[2])
      assert.equals(2, #dirs["/alpha"])
      assert.equals(1, #dirs["/zeta"])
    end)

    it("handles nil sources", function()
      local dirs, sorted = nodes.group_sources_by_dir(nil)
      assert.same({}, dirs)
      assert.same({}, sorted)
    end)
  end)

  describe("sort_sources_by_simple_name", function()
    it("sorts in-place by simple_name", function()
      local sources = {
        { simple_name = "z.adb" },
        { simple_name = "a.ads" },
        { simple_name = "m.ads" },
      }

      nodes.sort_sources_by_simple_name(sources)

      assert.equals("a.ads", sources[1].simple_name)
      assert.equals("m.ads", sources[2].simple_name)
      assert.equals("z.adb", sources[3].simple_name)
    end)
  end)

  describe("get_directory_files", function()
    local cleanup = nil

    after_each(function()
      if cleanup then
        cleanup()
        cleanup = nil
      end
    end)

    it("returns only direct files sorted alphabetically", function()
      local temp_root = os.tmpname()
      os.remove(temp_root)
      local dir = vim.fs.joinpath(temp_root, "obj")
      local nested = vim.fs.joinpath(dir, "nested")
      assert.equals(1, vim.fn.mkdir(nested, "p"))

      local b_file = vim.fs.joinpath(dir, "b.ali")
      local a_file = vim.fs.joinpath(dir, "a.adt")
      local nested_file = vim.fs.joinpath(nested, "inside.txt")

      local file = io.open(b_file, "w")
      assert.is_not_nil(file)
      file:write("")
      file:close()

      file = io.open(a_file, "w")
      assert.is_not_nil(file)
      file:write("")
      file:close()

      file = io.open(nested_file, "w")
      assert.is_not_nil(file)
      file:write("")
      file:close()

      cleanup = function()
        os.remove(nested_file)
        os.remove(a_file)
        os.remove(b_file)
        os.remove(nested)
        os.remove(dir)
        os.remove(temp_root)
      end

      local files = nodes.get_directory_files(dir)

      assert.equals(2, #files)
      assert.equals("a.adt", files[1])
      assert.equals("b.ali", files[2])
    end)
  end)

  describe("collect_subproject_entries", function()
    it("collects and sorts subprojects by name", function()
      local data = {
        projects = {
          a = { project = { id = "a", name = "alpha" } },
          b = { project = { id = "b", name = "beta" } },
          c = { project = { id = "c", name = "charlie" } },
        },
      }
      local entry = {
        imports = { "c" },
        aggregated = { "a" },
        extended = { "b" },
      }

      local result = nodes.collect_subproject_entries(entry, data)

      assert.equals(3, #result)
      assert.equals("alpha", result[1].project.name)
      assert.equals("beta", result[2].project.name)
      assert.equals("charlie", result[3].project.name)
    end)

    it("ignores missing subproject IDs", function()
      local data = {
        projects = {
          a = { project = { id = "a", name = "alpha" } },
        },
      }
      local entry = {
        imports = { "a", "missing" },
      }

      local result = nodes.collect_subproject_entries(entry, data)

      assert.equals(1, #result)
      assert.equals("a", result[1].project.id)
    end)
  end)

  describe("list_projects_flat", function()
    it("orders projects with root first then alphabetical", function()
      local data = {
        root_project_id = "root",
        projects = {
          lib = { project = { id = "lib", name = "z_lib" } },
          root = { project = { id = "root", name = "main" } },
          util = { project = { id = "util", name = "a_util" } },
        },
      }

      local list = nodes.list_projects_flat(data)

      assert.equals(3, #list)
      assert.equals("root", list[1].project.id)
      assert.equals("a_util", list[2].project.name)
      assert.equals("z_lib", list[3].project.name)
    end)
  end)
end)
