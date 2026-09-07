local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")

local RemotesConfig = require(script.Parent.Parent.Configs.RemotesConfig)

local remotes = {}

local function load(table, instanceName, parent)
     for _, name in pairs(table) do
          if parent:FindFirstChild(name) then continue end
          local event = Instance.new(instanceName)
          event.Name = name
          event.Parent = parent
     end
end     

remotes.init = function()
     local Events = Shared:FindFirstChild("Events")
     if not Events then
          Events = Instance.new("Folder")
          Events.Name = "Events"
          Events.Parent = Shared
     end    

     local Functions = Shared:FindFirstChild("Functions")
     if not Functions then
          Functions = Instance.new("Folder")
          Functions.Name = "Functions"
          Functions.Parent = Shared
     end    

     load(RemotesConfig.Events, "RemoteEvent", Events)
     load(RemotesConfig.Functions, "RemoteFunction", Functions)
end

return remotes