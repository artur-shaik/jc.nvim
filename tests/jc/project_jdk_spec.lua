describe("declared java level", function()
  local pj = require("jc.project_jdk")

  it("reads the level off the java extension", function()
    local d = pj._parse_gradle_level([[
subprojects {
    apply plugin: 'java'

    java {
        sourceCompatibility = 11
        targetCompatibility = 11
    }
}
]])
    assert.are.same({ level = 11, where = "java extension" }, d)
  end)

  it("flags a level set on the compile task, which the Tooling API misses", function()
    local d = pj._parse_gradle_level([[
subprojects {
    compileJava {
        options.encoding = "UTF-8"
        sourceCompatibility = 11
        targetCompatibility = 11
    }
}
]])
    assert.are.same({ level = 11, where = "compileJava task" }, d)
  end)

  it("prefers a toolchain, which does reach the Tooling API", function()
    local d = pj._parse_gradle_level([[
java {
    toolchain { languageVersion = JavaLanguageVersion.of(21) }
    sourceCompatibility = 11
}
]])
    assert.are.same({ level = 21, where = "toolchain" }, d)
  end)

  it("reads a maven pom, including the 1.8 spelling", function()
    assert.are.same(
      { level = 17, where = "pom property" },
      pj._parse_maven_level("<properties><maven.compiler.release>17</maven.compiler.release></properties>")
    )
    assert.are.same(
      { level = 8, where = "pom property" },
      pj._parse_maven_level("<properties><maven.compiler.source>1.8</maven.compiler.source></properties>")
    )
  end)

  it("reports nothing when the build declares no level", function()
    assert.is_nil(pj._parse_gradle_level("plugins { id 'java' }"))
    assert.is_nil(pj._parse_maven_level("<project></project>"))
  end)
end)

describe("project jdk findings", function()
  local pj = require("jc.project_jdk")

  local function ids(facts)
    local out = {}
    for _, f in ipairs(pj._findings(facts)) do
      out[#out + 1] = f.id
    end
    return out
  end

  it("says nothing when every level agrees", function()
    assert.are.same(
      {},
      ids({
        tool = "gradle",
        declared = { level = 11, where = "java extension" },
        compliance = 11,
        build_level = 11,
        bin_level = 11,
        buildship_home = "/j/11.0.12-open",
        method_parameters = "generate",
      })
    )
  end)

  it("catches the editor syncing gradle on another JDK", function()
    local findings = pj._findings({
      tool = "gradle",
      build_level = 11,
      buildship_home = "/home/me/.sdkman/candidates/java/17.0.7-oracle",
      method_parameters = "generate",
    })
    assert.are.equal("buildship_jdk", findings[1].id)
    assert.are.equal("buildship_jdk", findings[1].fix)
    assert.is_truthy(findings[1].message:find("JDK 17"))
    assert.is_truthy(findings[1].message:find("java 11"))
  end)

  it("names the compile task as the cause of a compliance mismatch", function()
    local findings = pj._findings({
      tool = "gradle",
      declared = { level = 11, where = "compileJava task" },
      compliance = 17,
      build_level = 11,
      method_parameters = "generate",
    })
    assert.are.equal("compliance", findings[1].id)
    assert.is_truthy(findings[1].hint:find("java { sourceCompatibility", 1, true))
    assert.is_nil(findings[1].fix) -- jc never rewrites build.gradle
  end)

  it("explains a plain compliance mismatch without blaming the task", function()
    local findings = pj._findings({
      tool = "gradle",
      declared = { level = 11, where = "java extension" },
      compliance = 17,
      build_level = 11,
      method_parameters = "generate",
    })
    assert.are.equal("compliance", findings[1].id)
    assert.is_nil(findings[1].hint:find("compile task", 1, true))
  end)

  it("reports split bytecode and missing parameter names", function()
    local findings = pj._findings({
      tool = "gradle",
      build_level = 11,
      bin_level = 17,
      method_parameters = "do not generate",
    })
    assert.are.same(
      { "bytecode_split", "method_parameters" },
      ids({
        tool = "gradle",
        build_level = 11,
        bin_level = 17,
        method_parameters = "do not generate",
      })
    )
    assert.are.equal("info", findings[1].severity)
  end)

  it("stays quiet about a project that was never built", function()
    assert.are.same({}, ids({ tool = "gradle", method_parameters = "generate" }))
  end)

  it("reads the JDK major out of assorted install layouts", function()
    assert.are.equal(11, pj._jdk_major("/home/me/.sdkman/candidates/java/11.0.12-open"))
    assert.are.equal(21, pj._jdk_major("/home/me/.sdkman/candidates/java/21.0.7.fx-zulu"))
    assert.are.equal(17, pj._jdk_major("/share/nvim/nvim-java/packages/openjdk/17/jdk-17.0.12"))
    assert.is_nil(pj._jdk_major(nil))
  end)
end)

describe("eclipse prefs rewriting", function()
  local pj = require("jc.project_jdk")

  it("replaces a key, appends a missing one, keeps the rest", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local file = dir .. "/prefs"
    vim.fn.writefile({ "auto.sync=false", "java.home=/old/jdk-17", "override.workspace.settings=true" }, file)

    assert.is_true(pj._set_pref(file, "java.home", "/new/11"))
    assert.are.same(
      { "auto.sync=false", "java.home=/new/11", "override.workspace.settings=true" },
      vim.fn.readfile(file)
    )

    assert.is_true(pj._set_pref(file, "gradle.user.home", "/gh"))
    assert.are.equal("gradle.user.home=/gh", vim.fn.readfile(file)[4])

    assert.is_false(pj._set_pref(dir .. "/missing", "java.home", "/x"))
    vim.fn.delete(dir, "rf")
  end)
end)
