local jsonFile = {}

local json = assert(loadfile("lib/json.lua"))()

local function file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

function jsonFile.load(fileName)
    print("Reading file: " .. fileName)
    if not file_exists(fileName) then
        print("jsonFile: Unable to find " .. fileName)
        return
    end

    assert(type(fileName) == 'string', 'Parameter "fileName" must be a string.');
    local file, err = io.open(fileName, 'rb')
    if not file then
        print("jsonFile: error opening file: " .. err)
    end
     -- LUA's *a/*all don't work so we need to do things the hard way
    local fileContent = ""
    local fileLine = io.read(file, "*L") -- Read first line (including newline)
    while fileLine do
        fileContent = fileContent .. fileLine -- Append as is (includes newlines)
        fileLine = io.read(file, "*L") -- Read next line
    end
    print("read file")
    print("got content: " .. fileContent)
    if fileContent == "" then
        print("jsonFile: file is empty")
        return {}
    end
    local data = json.decode(fileContent)
    io.close(file)
    return data;
end

function jsonFile.save(fileName, data)
    print("Writing file: " .. fileName)
    assert(type(fileName) == 'string', 'Parameter "fileName" must be a string.')
    assert(type(data) == 'table', 'Parameter "data" must be a table.')

    local file = io.open(fileName, 'w')
    local fileContent = json.encode(data)
    print("writing content: " .. fileContent)
    file:write(fileContent)
    io.close(file)

end

return jsonFile;
