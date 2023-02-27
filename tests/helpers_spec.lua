local helpers = require "lazy-lsp.helpers"

describe("lazy-lsp", function()
  it("escape_shell_arg", function()
    assert.same("'hello world'", helpers.escape_shell_arg("hello world"))
    assert.same("'h\"i'", helpers.escape_shell_arg("h\"i"))
    assert.same("'h'\"'\"'i'", helpers.escape_shell_arg("h'i"))
    assert.same("''", helpers.escape_shell_arg(""))
  end)

  it("escape_shell_args", function()
    assert.same("'hello world'", helpers.escape_shell_args({ "hello world" }))
    assert.same("'hello world' 'h\"i' 'h'\"'\"'i'", helpers.escape_shell_args({ "hello world", "h\"i", "h'i" }))
    assert.same("", helpers.escape_shell_args({}))
  end)

  describe("process_config", function()
    local lang_config = { document_config = { default_config = { cmd = { "ls_original_cmd" } } } }
    local empty_default_config = {}

    it("uses cmd from lspconfig", function()
      assert.same(
        { "nix-shell", "-p", "nix_pkg_name", "--run", "'ls_original_cmd'" },
        helpers.process_config(lang_config, nil, empty_default_config, "nix_pkg_name").cmd
      )
    end)

    it("servers config can specify multiple nix packages", function()
      assert.same(
        { "nix-shell", "-p", "nix_pkg_a", "nix_pkg_b", "--run", "'ls_original_cmd'" },
        helpers.process_config(lang_config, nil, empty_default_config, { pkgs = { "nix_pkg_a", "nix_pkg_b" } }).cmd
      )
    end)

    it("servers config can override cmd", function()
      assert.same(
        { "nix-shell", "-p", "nix_pkg_name", "--run", "'ls_server_cmd'" },
        helpers.process_config(
          lang_config, nil, empty_default_config, { cmd = { "ls_server_cmd" }, pkgs = { "nix_pkg_name" } }
        ).cmd
      )
    end)

    it("servers config can override cmd including arguments", function()
      assert.same(
        { "nix-shell", "-p", "nix_pkg_name", "--run", "'ls_server_cmd' '--lsp'" },
        helpers.process_config(
          lang_config, nil, empty_default_config, { cmd = { "ls_server_cmd", "--lsp" }, pkgs = { "nix_pkg_name" } }
        ).cmd
      )
    end)

    it("user specified cmd takes override priority", function()
      assert.same(
        { "nix-shell", "-p", "nix_pkg_name", "--run", "'ls_user_cmd'" },
        helpers.process_config(
          lang_config, { cmd = { "ls_user_cmd" } }, empty_default_config,
          { cmd = { "ls_server_cmd" }, pkgs = { "nix_pkg_name" } }
        ).cmd
      )
    end)

    it("when nix pkg is not available returns (will not setup ls)", function()
      assert.equals(
        nil,
        helpers.process_config(lang_config, nil, empty_default_config, "")
      )
    end)

    it("uses users config when nix pkg is not available", function()
      assert.same(
        { cmd = { "ls_user_cmd" } },
        helpers.process_config(lang_config, { cmd = { "ls_user_cmd" } }, empty_default_config, "")
      )
    end)

    it("merges default_config values", function()
      assert.same(
        nil,
        helpers.process_config(lang_config, nil, empty_default_config, "nix_pkg_name").some_undefined_parameter
      )
      assert.same(
        "some-value",
        helpers.process_config(lang_config, nil, { some_parameter = "some-value" }, "nix_pkg_name").some_parameter
      )
    end)

    it("merges default_config values when user config override is present", function()
      assert.same(
        "some-value",
        helpers.process_config(
          lang_config, { cmd = { "ls_user_cmd" } }, { some_parameter = "some-value" }, "nix_pkg_name"
        ).some_parameter
      )
    end)

    it("on_new_config does not error when lang config has no on_new_config function", function()
      local config = helpers.process_config(lang_config, nil, empty_default_config, "nix_pkg_name")
      config.on_new_config(config, "/some/root/path")
      assert.same(
        { "nix-shell", "-p", "nix_pkg_name", "--run", "'ls_original_cmd'" },
        config.cmd
      )
    end)

    it("on_new_config keeps original cmd if call back does not update it", function()
      local lang_config_with_on_new_config = {
        document_config = {
          default_config = {
            cmd = { "ls_original_cmd" },
            on_new_config = function(new_config, root_path)
            end
          }
        }
      }
      local config = helpers.process_config(lang_config_with_on_new_config, nil, empty_default_config, "nix_pkg_name")
      config.on_new_config(config, "/some/root/path")
      assert.same({ "nix-shell", "-p", "nix_pkg_name", "--run", "'ls_original_cmd'" }, config.cmd)
    end)

    it("on_new_config updates cmd when callback appends to it (e.g. omnisharp)", function()
      local lang_config_with_on_new_config = {
        document_config = {
          default_config = {
            cmd = { "ls_original_cmd" },
            on_new_config = function(new_config, root_path)
              table.insert(new_config.cmd, "--path")
              table.insert(new_config.cmd, root_path)
            end
          }
        }
      }
      local config = helpers.process_config(lang_config_with_on_new_config, nil, empty_default_config, "nix_pkg_name")
      config.on_new_config(config, "/some/root/path")
      assert.same(
        { "nix-shell", "-p", "nix_pkg_name", "--run", "'ls_original_cmd' '--path' '/some/root/path'" },
        config.cmd
      )
    end)

    it("on_new_config updates cmd when callback build a new one (e.g. eslint, codeqlls)", function()
      local lang_config_with_on_new_config = {
        document_config = {
          default_config = {
            cmd = { "ls_original_cmd" },
            on_new_config = function(new_config, root_path)
              new_config.cmd = { "new_cmd", "--path", root_path }
            end
          }
        }
      }
      local config = helpers.process_config(lang_config_with_on_new_config, nil, empty_default_config, "nix_pkg_name")
      config.on_new_config(config, "/some/root/path")
      -- Encoding current behavior, the presence of `ls_original_cmd` seems wrong, might need to fix it
      assert.same(
        { "nix-shell", "-p", "nix_pkg_name", "--run", "'ls_original_cmd' 'new_cmd' '--path' '/some/root/path'" },
        config.cmd
      )
    end)
  end)
end)