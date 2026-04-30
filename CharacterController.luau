local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TypeDefinitions = require(ReplicatedStorage.Common.TypeDefinitions)

local Log = require(ReplicatedStorage.Common.Log)
local ClientNetwork = require(ReplicatedStorage.Client.Modules.ClientNetwork)
local Raycast = require(ReplicatedStorage.Common.Raycast)
local InputController = require(ReplicatedStorage.Client.Controllers.InputController)
local WeaponController = require(ReplicatedStorage.Client.Controllers.WeaponController)
local CharacterStates = require(ReplicatedStorage.Client.Modules.Atoms.CharacterStates)
local Charm = require(ReplicatedStorage.Packages.Charm)
local CharacterStateController = require(ReplicatedStorage.Client.Controllers.CharacterStateController)
local ClientAtom = require(ReplicatedStorage.Client.Modules.Atoms.ClientAtoms)
local CameraAtoms = require(ReplicatedStorage.Client.Modules.Atoms.CameraAtoms)

local FLOOR_HEIGHT = 3.5

type Controller = TypeDefinitions.Controller

local CharacterController = {
	trackedCharacter = nil,
	ragdolled = nil,
	runService = nil,
} :: Controller & {
	runService: RBXScriptConnection?,
	ragdolled: any?,
	trackedCharacter: Model,
	onStart: () -> (),
	onCharacterAdded: (character: Model) -> (),
}

local function checkFloor(character: Model)
	if not character then
		return
	end

	if not character.PrimaryPart then
		return
	end

	local rayOrigin = character.PrimaryPart.Position
	local rayDirection = Vector3.new(0, -1, 0) * FLOOR_HEIGHT

	local hit = Raycast.raycast(rayOrigin, rayDirection, FLOOR_HEIGHT, { character }, true)

	if hit then
		-- for later
	end
end

function CharacterController.onStart()
	if CharacterController.runService then
		CharacterController.runService:Disconnect()
	end

	if CharacterController.ragdolled then
		CharacterController.ragdolled:Disconnect()
	end

	ClientNetwork.CharacterAdded.on(function(character)
		CharacterController.trackedCharacter = character
		CameraAtoms.cameraSubject(character:WaitForChild("Humanoid"))

		CharacterController.trackCharacter(CharacterController.trackedCharacter)
	end)

	CharacterController.ragdolled = Charm.subscribe(CharacterStates.ragdolled.value, function(isRagdolled)
		if not CharacterController.trackedCharacter then
			return
		end

		if not isRagdolled then
			CharacterController.ragdoll(false)
		else
			CharacterController.ragdoll(true)
		end
	end)

	CharacterController.runService = RunService.Heartbeat:Connect(function()
		if CharacterController.trackedCharacter then
			checkFloor(CharacterController.trackedCharacter)
		end
	end)
end

function CharacterController.ragdoll(state: boolean)
	if CharacterController.trackedCharacter then
		local humanoid = CharacterController.trackedCharacter:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		if state then
			for _, v in pairs(humanoid:GetPlayingAnimationTracks()) do
				v:Stop(0)
			end
		end

		CharacterController.trackedCharacter.Animate.Disabled = state
		humanoid:ChangeState(state and Enum.HumanoidStateType.Physics or Enum.HumanoidStateType.GettingUp)
		ClientNetwork.RagdollCharacter.fire(state)
	end
end

function CharacterController.trackCharacter(character: Model)
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then
			ClientAtom.tool(child)
			WeaponController.equip(child)
		end
	end)

	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then
			ClientAtom.tool(nil)
			WeaponController.unequip()
		end
	end)
end

return CharacterController
