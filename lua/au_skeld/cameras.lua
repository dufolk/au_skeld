
if SERVER then
	-- Entity targetname for the button which opens cameras
	local BUTTON_NAME = 'camera_button'
	-- VGUI state name to use
	local VGUI_NAME = 'securityCams'
	-- Entity targetname for the physical camera props
	local PROP_NAME = 'security_cam'
	-- Prefix of the entity targetname for the invisible camera viewpoints
	-- Not positioned exactly at the security_cam props to allow more viewpoint flexibility
	local VIEWPOINT_NAME_PREFIX = 'camera_viewpoint_'

	local playersOnCameras = {}

	local function getCameraViewpointEnts()
		local cameraData = {}

		for i, v in ipairs(ents.GetAll()) do
			if IsValid(v) and string.sub(v:GetName(), 1, string.len(VIEWPOINT_NAME_PREFIX)) == VIEWPOINT_NAME_PREFIX then
				local viewpointName = string.sub(v:GetName(), string.len(VIEWPOINT_NAME_PREFIX) + 1)
				cameraData[viewpointName] = {
					pos   = v:GetPos(),
					angle = v:GetAngles()
				}
			end
		end

		return cameraData
	end

	local function updateCameraModels()
		local numPlayersOnCams = 0

		for _, v in pairs(playersOnCameras) do
			if v then
				numPlayersOnCams = numPlayersOnCams + 1
			end
		end

		for i, v in ipairs(ents.FindByName(PROP_NAME)) do
			local skin = numPlayersOnCams > 0 and 1 or 0
			v:SetSkin(skin)
		end
	end

	local function openCameras(ply)
		if not ply:IsPlaying() then return end
		local playerTable = ply:GetAUPlayerTable()

		local payload = { cameraData = getCameraViewpointEnts() }
		
		if IsValid(ply) and not ply:IsDead() then
			playersOnCameras[playerTable] = true
			updateCameraModels()
		end

		GAMEMODE:Player_OpenVGUI(playerTable, VGUI_NAME, payload, function()
			playersOnCameras[playerTable] = false
			updateCameraModels()
		end)
	end

	-- Debugging command. Ignore.
	-- concommand.Add('au_debug_open_cameras', openCameras)

	hook.Add('PlayerUse', 'au_skeld cameras monitor use', function (ply, ent)
		if ent:GetName() == BUTTON_NAME then
			openCameras(ply)
		end
	end)

	hook.Add('SetupPlayerVisibility', 'au_skeld cameras add PVS', function (ply, viewEnt)
		if ply:GetCurrentVGUI() ~= VGUI_NAME then return end -- player not on cams
		if GAMEMODE:GetCommunicationsDisabled() then return end

		for k, v in pairs(getCameraViewpointEnts()) do
			AddOriginToPVS(v.pos)
		end
	end)

	hook.Add('GMAU GameStart', 'au_skeld cameras cleanup', function ()
		playersOnCameras = {}
		updateCameraModels()
	end)

	local function fixupUseHighlight()
		local ent = ents.FindByName(BUTTON_NAME)[1]
		if IsValid(ent) then
			GAMEMODE:SetUseHighlight(ent, true)
			ent:SetNWBool('au_skeld_IsCameraButton', true)
		end
	end

	hook.Add('InitPostEntity', 'au_skeld VGUI_NAME button highlight', fixupUseHighlight)
	hook.Add('PostCleanupMap', 'au_skeld VGUI_NAME button highlight', fixupUseHighlight)
else
	local noop = function() end
	local CAMERA_ORDER = {
		'navigation',   'admin',
		'upper_engine', 'security',
	}
	local NOISE_MAT = Material('au_skeld/gui/noise.png')
	local BUTTON_MAT = Material('au_skeld/gui/security_button.png', 'smooth')
	local BACKGROUND_MAT = Material('au_skeld/gui/cameras_background.png', 'smooth')
	local MONITOR_MAT = Material('au_skeld/gui/cameras_monitor.png', 'smooth')
	local GRADIENT_MAT = Material('au_skeld/gui/gradient.png', 'smooth')
	local NOISE_COLOR = Color(189, 247, 224)
	local COLOR_RED = Color(255, 0, 0)
	local NOISE_SCROLL_SPEED = 100
	local TEXT_FLASH_SPEED = 150

	local inRenderView = false

	hook.Add('GMAU Lights ShouldFade', 'au_skeld cameras disable light fade', function ()
		if inRenderView then return false end
	end)

	surface.CreateFont('au_skeld CamsSabotaged', {
		font = 'Lucida Console',
		size = ScreenScale(15),
		weight = 400,
		outline = true,
	})

	local function _(str)
		return GAMEMODE.Lang.GetEntry(str)()
	end

	hook.Add('GMAU UseButtonOverride', 'au_skeld cameras use button', function (ent)
		if ent:GetNWBool('au_skeld_IsCameraButton') then return BUTTON_MAT end
	end)

	hook.Add('GMAU OpenVGUI', 'au_skeld cameras GUI open', function(payload)
		if not payload.cameraData then return end

		local base = vgui.Create('AmongUsVGUIBase')

		local bgWidth, bgHeight = GAMEMODE.Render.FitMaterial(BACKGROUND_MAT, ScrW(), ScrH())
		local bgAspectRatio = bgWidth/bgHeight
		local bgDrawWidth = bgAspectRatio * ScrH()

		local animationTable, value

		function base:Paint(w, h)
			if not value or not animationTable then return end
			if not animationTable.closing and value < 0.5 then return end
			if animationTable.closing and value > 0.5 then return end

			surface.SetMaterial(BACKGROUND_MAT)
			surface.SetDrawColor(255, 255, 255)
			surface.DrawTexturedRect(w/2-bgDrawWidth/2, 0, bgDrawWidth, h)
			if not animationTable.closing and value > 0.5 then
				surface.SetDrawColor(255, 255, 255, 255)
				surface.SetMaterial(GRADIENT_MAT)
				surface.DrawTexturedRect(0, 0, w * 0.5, h)
				surface.DrawTexturedRectUV(w * 0.5, 0, w * 0.5, h, 1, 0, 0, 1)
			end
		end

		function base:PaintOver(w, h)
			if not animationTable then return end

			value = (animationTable.EndTime - SysTime()) / (animationTable.EndTime - animationTable.StartTime)
			value = math.min(1-value, 1)

			if value < 0.5 then
				-- fade out
				surface.SetDrawColor(0, 0, 0, value * 2 * 255)
			else
				-- fade in
				surface.SetDrawColor(0, 0, 0, (1-value) * 2 * 255)
			end

			surface.DrawRect(0, 0, w, h)
		end

		local panel = vgui.Create('Panel')
		local minDim = 0.98 * math.min(ScrW(), ScrH())
		local width, height = GAMEMODE.Render.FitMaterial(MONITOR_MAT, minDim, minDim)
		local margin = math.min(width, height) * 0.02
		panel:SetSize(width, height)
		function panel:Paint(w, h)
			surface.SetDrawColor(NOISE_COLOR)
			surface.DrawRect(margin/2, margin/2, w-margin, h-margin)
		end
		function panel:PaintOver(w, h)
			surface.SetMaterial(MONITOR_MAT)
			surface.SetDrawColor(255, 255, 255)
			surface.DrawTexturedRect(0, 0, w, h)
		end

		for i = 0, 1 do
			local row = panel:Add('Panel')
			row:SetTall(height/2)
			row:Dock(TOP)

			for j = 1, 2 do
				local curCameraName = CAMERA_ORDER
		[(i * 2) + j]
				local curCamera = payload.cameraData[curCameraName]

				local camContainer = row:Add('Panel')
				camContainer:SetWide(width/2)
				camContainer:Dock(LEFT)

				local cam = camContainer:Add('DPanel')
				cam:DockMargin(
					margin,
					i == 1 and 0 or margin,
					j == 1 and 0 or margin,
					i == 2 and 0 or margin
				)
				cam:Dock(FILL)

				if curCamera then
					function cam:Paint(w, h)
						local x, y = self:LocalToScreen(0, 0)

						local oldHalo = halo.Render
						halo.Render = noop
						
						if not GAMEMODE:GetCommunicationsDisabled() then
							inRenderView = true
							render.RenderView {
								aspectratio = w/h,
								origin = curCamera.pos,
								angles = curCamera.angle,
								x = x,
								y = y,
								w = w,
								h = h,
								fov = 125,
								drawviewmodel = false,
							}
							inRenderView = false
						else
							-- comms disabled, show noise and flashing text
							surface.SetMaterial(NOISE_MAT)
							local time = SysTime() * NOISE_SCROLL_SPEED
							render.PushFilterMin(TEXFILTER.LINEAR)
							render.PushFilterMag(TEXFILTER.LINEAR)
							surface.SetDrawColor(NOISE_COLOR)
							surface.DrawTexturedRectUV(
								0, 0, w, h,
								time % 1,         0,
								(time + w/h) % 1, 1
							)
							render.PopFilterMag()
							render.PopFilterMin()

							if time % TEXT_FLASH_SPEED < TEXT_FLASH_SPEED/2 then
								draw.SimpleText('[' .. string.upper(_('tasks.commsSabotaged')) .. ']', 'au_skeld CamsSabotaged', w/2, h/2, COLOR_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
							end
						end

						halo.Render = oldHalo
					end
				else
					print('[?!?] Camera ' .. curCameraName .. ' missing from payload?')
					function cam:Paint(w, h)
						surface.SetDrawColor(COLOR_RED)
						surface.DrawRect(0, 0, w, h)
					end
				end
			end
		end

		base:Setup(panel)

		function base:Popup()
			self:MakePopup()
			self:SetKeyboardInputEnabled(false)
			self:SetVisible(true)
			self:SetAlpha(255)
			panel:Hide()
			self:NewAnimation(0.25, 0, 0, function()
				panel:Show()
			end)
			self:SetPos(0, 0)
			self.__isOpened = true

			animationTable = self:NewAnimation(0.5, 0, 0, function ()
				if self.OnOpen then
					self:OnOpen()
				end
			end)

			animationTable.closing = false

			return true
		end

		function base:Close()
			self:NewAnimation(0.25, 0, 0, function()
				panel:Hide()
				self:SetMouseInputEnabled(false)
				self:GetCloseButton():Hide()
			end)
			self.__isOpened = false

			animationTable = self:NewAnimation(0.5, 0, 0, function ()
				if self.OnClose then
					self:OnClose()
				end
	
				if self:GetDeleteOnClose() then
					self:Remove()
				else
					self:SetVisible(false)
				end
			end)

			animationTable.closing = true
	
			return true
		end

		panel:AlignTop(ScrH()*0.03)
		base:Popup()

		GAMEMODE:HUD_OpenVGUI(base)

		return true
	end)
end
