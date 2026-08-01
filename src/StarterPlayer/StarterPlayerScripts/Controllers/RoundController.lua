--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Comm = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Comm"))
local Trove = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Trove"))

local NetData = require(ReplicatedStorage:WaitForChild("Data"):WaitForChild("Net"))
local Format = require(ReplicatedStorage:WaitForChild("Utils"):WaitForChild("Format"))

type TroveType = typeof(Trove.new())
type RoundControllerType = {
	_serviceTrove: TroveType,
	_pulseTween: Tween?,
	_roundComm: any,
	_roundProperty: any,
	hud: any,
	frame: any,
	roundLabel: TextLabel,
	timer: TextLabel,
	onStart: (self: RoundControllerType) -> (),
}

local player = Players.LocalPlayer

local RoundController = {
	_serviceTrove = Trove.new(),
	_pulseTween = nil,
	_roundComm = nil :: any,
	_roundProperty = nil :: any,
	hud = nil :: any,
	frame = nil :: any,
	roundLabel = nil :: any,
	timer = nil :: any,
} :: RoundControllerType

local function stopPulseTween(self: RoundControllerType)
	if self._pulseTween then
		self._pulseTween:Cancel()
		self._pulseTween = nil
	end
	self.timer.TextColor3 = Color3.new(1, 1, 1)
end

local function renderRound(self: RoundControllerType, state: any)
	if type(state) ~= "table" then
		return
	end

	local secondsLeft = state.secondsLeft
	if type(secondsLeft) ~= "number" then
		return
	end

	if state.state == "WaitingForPlayers" then
		self.roundLabel.Text = "Waiting for Players"
	elseif state.state == "RoundStartCountdown" then
		self.roundLabel.Text = "Round 1 starting soon"
	else
		local roundNumber = state.round
		local displayRound = type(roundNumber) == "number" and roundNumber > 0 and roundNumber or 1
		self.roundLabel.Text = "Round " .. displayRound
	end
	self.timer.Text = Format.formatSeconds(secondsLeft)
	if secondsLeft < 10 and secondsLeft > 0 then
		if not self._pulseTween then
			local pulseTween = TweenService:Create(
				self.timer,
				TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{
					TextColor3 = Color3.fromRGB(255, 72, 72),
				}
			)
			self._pulseTween = pulseTween
			pulseTween:Play()
		end
	else
		stopPulseTween(self)
	end
end

local function connectUiReferences(self: RoundControllerType)
	local playerGui = player:WaitForChild("PlayerGui")
	self.hud = playerGui:WaitForChild("RoundHUD")
	self.frame = self.hud.Frame
	self.roundLabel = self.frame.RoundLabel
	self.timer = self.frame.Timer
end

local function connectSignals(self: RoundControllerType)
	self._roundComm = Comm.ClientComm.new(ReplicatedStorage, false, NetData.round.namespace)
	self._roundProperty = self._roundComm:GetProperty(NetData.round.state)
	self._serviceTrove:Add(self._roundProperty:Observe(function(state)
		renderRound(self, state)
	end))
end

function RoundController.onStart(self: RoundControllerType): ()
	connectUiReferences(self)
	connectSignals(self)
end

return RoundController
