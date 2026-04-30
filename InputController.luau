local CAS = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientAtoms = require(ReplicatedStorage.Client.Modules.Atoms.ClientAtoms)
local ClientEvents = require(ReplicatedStorage.Client.Modules.ClientEvents)
local TypeDefinitions = require(ReplicatedStorage.Common.TypeDefinitions)
local Keybinds = require(ReplicatedStorage.Common.Keybinds)
local Log = require(ReplicatedStorage.Common.Log)

type Controller = TypeDefinitions.Controller
type ActionCallback = (actionName: string, inputState: Enum.UserInputState, inputObject: InputObject?) -> ()

type InputType = Enum.KeyCode | Enum.UserInputType

export type ActionData = {
	callback: ActionCallback, -- user callback
	priority: number,
	keycodes: { Enum.KeyCode }, -- kept for backwards-compat / readability
	mouseInputs: { Enum.UserInputType }, -- NEW: mouse-related inputs
	requiredState: Enum.UserInputState?, -- if set, only fire when inputState == requiredState
	enabled: boolean?,
}

local InputController = {
	activeKeybind = {} :: { [string]: ActionData },
} :: Controller & {
	activeKeybind: { [string]: ActionData },

	getAction: (name: string) -> ActionCallback?,
	bindAction: (
		name: string,
		callback: ActionCallback,
		keycodes: { Enum.KeyCode }?,
		priority: number?,
		inputState: Enum.UserInputState?,
		mouseInputs: { Enum.UserInputType }?
	) -> (),
	updateAction: (
		name: string,
		input: {
			callback: ActionCallback?,
			priority: number?,
			keycodes: { Enum.KeyCode }?,
			requiredState: Enum.UserInputState?,
			mouseInputs: { Enum.UserInputType }?,
		}
	) -> (),
	refreshBinds: () -> (),
	triggerAction: (name: string) -> (),
	onStart: () -> (),
}

function InputController.getAction(name: string)
	local data = InputController.activeKeybind[name]
	return if data then data.callback else nil
end

-- internal: (re)bind one action with a wrapper that enforces requiredState
local function rebind(name: string, data: ActionData)
	CAS:UnbindAction(name)

	-- Merge all provided inputs (keyboard + mouse) for binding
	local inputs: { InputType } = {}
	for _, kc in ipairs(data.keycodes) do
		table.insert(inputs, kc)
	end
	for _, mi in ipairs(data.mouseInputs) do
		table.insert(inputs, mi)
	end

	if data.enabled == false or #inputs == 0 then
		return
	end

	-- Wrapper ensures state filter is respected before calling user callback.
	local function wrappedCallback(aName, inputState, inputObject)
		if data.requiredState == nil or inputState == data.requiredState then
			local result = data.callback(aName, inputState, inputObject)

			if result ~= nil then
				return result
			end
		end

		return Enum.ContextActionResult.Pass
	end

	CAS:BindActionAtPriority(name, wrappedCallback, false, data.priority, table.unpack(inputs))
end

-- keycodes optional; only bind if provided and non-empty
function InputController.bindAction(
	name: string,
	callback: ActionCallback,
	keycodes: { Enum.KeyCode }?,
	priority: number?,
	inputState: Enum.UserInputState?,
	mouseInputs: { Enum.UserInputType }?
)
	local data: ActionData = {
		callback = callback,
		priority = priority or 0,
		keycodes = keycodes or {},
		mouseInputs = mouseInputs or {}, -- NEW
		requiredState = inputState, -- nil means no filtering
		enabled = true,
	}

	InputController.activeKeybind[name] = data
	rebind(name, data)
end

function InputController.unbindAction(name: string)
	local data = InputController.activeKeybind[name]

	if not data then
		Log.warn("Keybind does not exist", { name = name })
		return
	end

	CAS:UnbindAction(name)
	data.enabled = false
end

function InputController.updateAction(
	name: string,
	input: {
		callback: ActionCallback?,
		priority: number?,
		keycodes: { Enum.KeyCode }?,
		mouseInputs: { Enum.UserInputType }?, -- NEW
		requiredState: Enum.UserInputState?,
	}
)
	local data = InputController.activeKeybind[name]
	if not data then
		Log.warn("Keybind does not exist", { name = name })
		return
	end

	if input.callback ~= nil then
		data.callback = input.callback
	end
	if input.priority ~= nil then
		data.priority = input.priority
	end
	if input.keycodes ~= nil then
		data.keycodes = input.keycodes
	end
	if input.mouseInputs ~= nil then
		data.mouseInputs = input.mouseInputs
	end
	if input.requiredState ~= nil then
		data.requiredState = input.requiredState
	end

	rebind(name, data)
end

function InputController.refreshBinds()
	for name, data in pairs(InputController.activeKeybind) do
		rebind(name, data)
	end
end

function InputController.triggerAction(name: string)
	local data = InputController.activeKeybind[name]
	if not data then
		Log.warn("Keybind does not exist", { name = name })
		return
	end

	-- If a required state is set, simulate with that; otherwise use Begin.
	local simulatedState = data.requiredState or Enum.UserInputState.Begin
	data.callback(name, simulatedState, nil)
end

function InputController.onStart()
	for actionKey, entry in Keybinds do
		local name = tostring(actionKey)
		local key = entry.key

		local codes: { Enum.KeyCode } = {}
		if key ~= nil then
			if typeof(key) == "EnumItem" then
				codes = { key :: Enum.KeyCode }
			elseif typeof(key) == "table" then
				codes = key :: { Enum.KeyCode }
			end
		end

		InputController.bindAction(name, function(aName, inputState, _inputObject)
			if inputState == Enum.UserInputState.Begin then
				if actionKey == "Leaderboard" then
					ClientAtoms.leaderboardOpen(not ClientAtoms.leaderboardOpen())
				elseif actionKey == "Radio" then
					ClientAtoms.radioEnabled(not ClientAtoms.radioEnabled())
				elseif actionKey == "HideRadio" then
					ClientEvents.fire("ShowMenu", { menu = "Radio" })
				end
			end
		end, codes, 0)
	end

	InputController.refreshBinds()
end

return InputController
