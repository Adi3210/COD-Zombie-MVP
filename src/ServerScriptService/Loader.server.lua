--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Loader = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Loader"))

local modules = script.Parent:WaitForChild("Services")

Loader.SpawnAll(Loader.LoadDescendants(modules, Loader.MatchesName("Service$")), "onStart")
