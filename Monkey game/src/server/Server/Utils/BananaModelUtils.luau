--!strict

local bananaModelUtils = {}

function bananaModelUtils.prepare(model: Model, anchored: boolean): BasePart?
	local rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if not rootPart then
		return nil
	end

	model.PrimaryPart = rootPart
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false

			if descendant ~= rootPart then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "BananaWeld"
				weld.Part0 = rootPart
				weld.Part1 = descendant
				weld.Parent = rootPart
			end
		end
	end

	rootPart.Anchored = anchored
	return rootPart
end

return bananaModelUtils
