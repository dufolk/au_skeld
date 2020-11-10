if SERVER then
	local function getCameras()
		local cameraPrefix = 'camera_viewpoint_'
		local cameraData = {}

		for i, v in ipairs(ents.GetAll()) do
			if IsValid(v) and string.sub(v:GetName(), 1, string.len(cameraPrefix)) == cameraPrefix then
				local cameraName = string.sub(v:GetName(), string.len(cameraPrefix) + 1)
				cameraData[cameraName] = {
					pos   = v:GetPos(),
					angle = v:GetAngles()
				}
			end
		end

		return cameraData
	end

	local function openCameras(ply)
		-- This isn't particularly nice, I know.
		-- I just don't have any fancy wrappers yet.
		local playerTable = GAMEMODE.GameData.Lookup_PlayerByEntity[ply]
		if not playerTable then return end

		local payload = { cameraData = getCameras() }

		GAMEMODE:Player_OpenVGUI(playerTable, 'securityCams', payload) 
	end

	concommand.Add('au_debug_open_cameras', openCameras)

	hook.Add('PlayerUse', 'au_skeld cameras monitor use', function(ply, ent)
		if ent:GetName() == 'camera_button' then
			openCameras(ply)
		end
	end)

	hook.Add('SetupPlayerVisibility', 'au_skeld cameras add PVS', function (ply, viewEnt)
		local playerTable = GAMEMODE.GameData.Lookup_PlayerByEntity[ply]
		if not playerTable then return end -- player not found?
		if GAMEMODE.GameData.CurrentVGUI[playerTable] ~= 'securityCams' then return end -- player not on cams

		for k, v in pairs(getCameras()) do
			AddOriginToPVS(v.pos)
		end
	end)
else
	local noop = function() end
	local cameraOrder = {
		'navigation',   'admin',
		'upper_engine', 'security',
	}
	local orthos = {
		navigation = {
			top = -275,
			bottom = 275,
			left = -250,
			right = 250,
		},
		admin = {
			top = -150,
			bottom = 250,
			left = -225,
			right = 165,
		},
		upper_engine = {
			top = -125,
			bottom = 300,
			left = -300,
			right = 300,
		},
		security = {
			top = -175,
			bottom = 175,
			left = -180,
			right = 180,
		}
	}

	hook.Add('GMAU OpenVGUI', 'au_skeld cameras GUI open', function(payload)
		if not payload.cameraData then return end

		local base = vgui.Create('AmongUsVGUIBase')
		local panel = vgui.Create('DPanel')
		local width = 0.55 * ScrW()
		local height = 0.7 * ScrH()
		local margin = math.min(width, height) * 0.03
		panel:SetSize(width, height)
		panel:SetBackgroundColor(Color(64, 64, 64))

		for i = 0, 1 do
			local row = panel:Add('DPanel')
			row:SetTall(height/2)
			row:Dock(TOP)
			row.Paint = function() end

			for j = 1, 2 do
				local curCameraName = cameraOrder[(i * 2) + j]
				local curCamera = payload.cameraData[curCameraName]

				local camContainer = row:Add('DPanel')
				camContainer:SetWide(width/2)
				camContainer:Dock(LEFT)
				camContainer.Paint = function() end

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
						-- XD
						oldHalo = halo.Render
						halo.Render = noop

						local x, y = self:LocalToScreen(0, 0)
						render.RenderView( {
							aspectratio = w/h,
							origin = curCamera.pos,
							angles = curCamera.angle,
							x = x,
							y = y,
							w = w,
							h = h,
							fov = 75,
							drawviewmodel = false,
							ortho = orthos[curCameraName],
						})

						halo.Render = oldHalo
					end
				else
					print('[?!?] Camera ' .. curCameraName .. ' missing from payload?')
					function cam:Paint(w, h)
						surface.SetDrawColor(Color(255, 0, 0))
						surface.DrawRect(0, 0, w, h)
					end
				end
			end
		end

		base:Setup(panel)
		base:Popup()

		GAMEMODE:HUD_OpenVGUI(base)

		return true
	end)
end