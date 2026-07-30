--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Loader"))

local modules = script.Parent:WaitForChild("Controllers")

Loader.SpawnAll(Loader.LoadDescendants(modules, Loader.MatchesName("Controller$")), "onStart")
