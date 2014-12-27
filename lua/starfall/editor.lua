-------------------------------------------------------------------------------
-- SF Editor.
-- Functions for setting up the code editor, as well as helper functions for
-- sending code over the network.
-------------------------------------------------------------------------------

SF.Editor = {}

-- TODO: Server-side controls

--- Includes table
-- @name Includes table
-- @class table
-- @field mainfile Main file
-- @field files filename : file contents pairs

if CLIENT then

	local invalid_filename_chars = {
		["*"] = "",
		["?"] = "",
		[">"] = "",
		["<"] = "",
		["|"] = "",
		["\\"] = "",
		['"'] = "",
		[" "] = "_",
	}

	local keywords = {
		["if"] = true,
		["elseif"] = true,
		["else"] = true,
		["then"] = true,
		["end"] = true,
		
		["while"] = true,
		["for"] = true,
		["in"] = true,
		
		["do"] = true,
		["repeat"] = true,
		["until"] = true,
		
		["function"] = true,
		["local"] = true,
		["return"] = true,
		
		["and"] = true,
		["or"] = true,
		["not"] = true,
		
		["true"] = true,
		["false"] = true,
		["nil"] = true,
	}
	
	local operators = {
		["+"] = true,
		["-"] = true,
		["/"] = true,
		["*"] = true,
		["^"] = true,
		["%"] = true,
		["#"] = true,
		["="] = true,
		["=="] = true,
		["~="] = true,
		[","] = true,
		["."] = true,
		["<"] = true,
		[">"] = true,
		
		["{"] = true,
		["}"] = true,
		["("] = true,
		[")"] = true,
		["["] = true,
		["]"] = true,
		
		["_"] = true,
	}
	
	--[[
	-- E2 colors
	local colors = {
		["keyword"]		= { Color(160,240,240), false }, -- teal
		["operator"]	= { Color(224,224,224), false }, -- white
		["brackets"]	= { Color(224,224,224), false }, -- white
		
		["function"]	= { Color(160,160,240), false }, -- blue
		["number"]		= { Color(240,160,160), false }, -- light red
		["variable"]	= { Color(160,240,160), false }, -- green
		
		["string"]		= { Color(160,160,160), false }, -- gray
		["comment"]		= { Color(160,160,160), false }, -- gray
		
		["ppcommand"]	= { Color(240,240,160), false }, -- pink
		["notfound"]	= { Color(240, 96, 96), false }, -- dark red
	}

	-- Colors originally by Cenius; slightly modified by Divran
	local colors = {
		["keyword"]		= { Color(160, 240, 240), false},
		["operator"]	= { Color(224, 224, 224), false},
		["brackets"]	= { Color(224, 224, 224), false},
		["function"]	= { Color(160, 160, 240), false}, -- Was originally called "expression"
		
		["number"]		= { Color(240, 160, 160), false}, 
		["string"]		= { Color(160, 160, 160), false}, -- Changed to lighter grey so it isn't the same as comments
		["variable"]	= { Color(180, 180, 260), false}, -- Was originally called "globals".
		
		--["comment"] 	= { Color(0, 255, 0), false}, -- Cenius' original comment color was green... imo not very nice
		["comment"]		= { Color(128,128,128), false }, -- Changed to grey
		
		["ppcommand"]	= { Color(240, 240, 160), false},
		
		["notfound"]	= { Color(240,  96,  96), false}, 
	}
	]]
	local colors = {
		["keyword"]     = { Color(100, 100, 255), false},
		["operator"]    = { Color(150, 150, 200), false},
		["brackets"]    = { Color(120, 120, 255), false},
		["number"]      = { Color(174, 129, 255), false},
		["variable"]    = { Color(248, 248, 242), false},
		["string"]      = { Color(230, 219, 116), false},
		["comment"]     = { Color(133, 133, 133), false},
		["ppcommand"]   = { Color(170, 170, 170), false},
		["notfound"]    = { Color(240,  96,  96), false},
	}
	
	-- cols[n] = { tokendata, color }
	local cols = {}
	local lastcol
	local function addToken(tokenname, tokendata)
		local color = colors[tokenname]
		if lastcol and color == lastcol[2] then
			lastcol[1] = lastcol[1] .. tokendata
		else
			cols[#cols + 1] = { tokendata, color, tokenname }
			lastcol = cols[#cols]
		end
	end
	
	local string_gsub = string.gsub
	local string_find = string.find
	local string_sub = string.sub
	local string_format = string.format
	
	local function findStringEnding(self,row,char)
		char = char or '"'
		
		while self.character do
			if self:NextPattern( ".-"..char ) then -- Found another string char (' or ")
				if self.tokendata[#self.tokendata-1] ~= "\\" then -- Ending found
					return true
				end
			else -- Didn't find another :(
				return false
			end
			
			self:NextCharacter()		
		end
		
		return false
	end

	local function findMultilineEnding(self,row,what) -- also used to close multiline comments
		if self:NextPattern( ".-%]%]" ) then -- Found ending
			return true
		end
		
		self.multiline = what
		return false
	end
	
	local table_concat = table.concat
	local string_gmatch = string.gmatch
	
	local function findInitialMultilineEnding(self,row,what)
		if row == self.Scroll[1] then
			-- This code checks if the visible code is inside a string or a block comment
			self.multiline = nil
			local singleline = false

			local str = string_gsub( table_concat( self.Rows, "\n", 1, self.Scroll[1]-1 ), "\r", "" )
			
			for before, char, after in string_gmatch( str, "()([%-\"'\n%[%]])()" ) do
				before = string_sub( str, before-1, before-1 )
				after = string_sub( str, after, after+2 )
				
				if not self.multiline and not singleline then
					if char == '"' or char == "'" or (char == "-" and after[1] == "-" and after ~= "-[[") then
						singleline = true
					elseif char == "-" and after == "-[[" then
						self.multiline = "comment"
					elseif char == "[" and after[1] == "[" then
						self.multiline = "string"
					end
				elseif singleline and ((char == "'" or char == '"') and before ~= "\\" or char == "\n") then
					singleline = false
				elseif self.multiline and char == "]" and after[1] == "]" then
					self.multiline = nil
				end
			end
		end
	end

	-- TODO: remove all the commented debug prints
	local function SyntaxColorLine(self,row)
		cols,lastcol = {}, nil
		self:ResetTokenizer(row)
		findInitialMultilineEnding(self,row,self.multiline)
		self:NextCharacter()
		
		if self.multiline then
			if findMultilineEnding(self,row,self.multiline) then
				addToken( self.multiline, self.tokendata )
				self.multiline = nil
			else
				self:NextPattern( ".*" )
				addToken( self.multiline, self.tokendata )
				return cols
			end
			self.tokendata = ""
		end

		while self.character do
			self.tokendata = ""
			
			-- Eat all spaces
			local spaces = self:SkipPattern( "^%s*" )
			if spaces then addToken( "comment", spaces ) end
	
			if self:NextPattern( "^%a[%w_]*" ) then -- Variables and keywords
				if keywords[self.tokendata] then
					addToken( "keyword", self.tokendata )
				else
					addToken( "variable", self.tokendata )
				end
			elseif self:NextPattern( "^%d*%.?%d+" ) then -- Numbers
				addToken( "number", self.tokendata )
			elseif self:NextPattern( "^%-%-" ) then -- Comment
				if self:NextPattern( "^@" ) then -- ppcommand
					self:NextPattern( ".*" ) -- Eat all the rest
					addToken( "ppcommand", self.tokendata )
				elseif self:NextPattern( "^%[%[" ) then -- Multi line comment
					if findMultilineEnding( self, row, "comment" ) then -- Ending found
						addToken( "comment", self.tokendata )
					else -- Ending not found
						self:NextPattern( ".*" )
						addToken( "comment", self.tokendata )
					end
				else
					self:NextPattern( ".*" ) -- Skip the rest
					addToken( "comment", self.tokendata )
				end
			elseif self:NextPattern( "^[\"']" ) then -- Single line string
				if findStringEnding( self,row, self.tokendata ) then -- String ending found
					addToken( "string", self.tokendata )
				else -- No ending found
					self:NextPattern( ".*" ) -- Eat everything
					addToken( "string", self.tokendata )
				end
			elseif self:NextPattern( "^%[%[" ) then -- Multi line strings
				if findMultilineEnding( self, row, "string" ) then -- Ending found
					addToken( "string", self.tokendata )
				else -- Ending not found
					self:NextPattern( ".*" )
					addToken( "string", self.tokendata )
				end
			elseif self:NextPattern( "^[%+%-/%*%^%%#=~,;:%._<>]" ) then -- Operators
				addToken( "operator", self.tokendata )
			elseif self:NextPattern("^[%(%)%[%]{}]") then
				addToken( "brackets", self.tokendata)
			else
				self:NextCharacter()
				addToken( "notfound", self.tokendata )
			end
			self.tokendata = ""
		end
		
		return cols
	end
	
	local code1 = "--@name \n--@author \n\n"
	local code2 = "--[[\n" .. [[    Starfall Scripting Environment

    More info: http://gmodstarfall.github.io/Starfall/
    Reference Page: http://sf.inp.io
    Development Thread: http://www.wiremod.com/forum/developers-showcase/22739-starfall-processor.html
]] .. "]]"

	--- (Client) Intializes the editor, if not initialized already
	function SF.Editor.init()
		if SF.Editor.editor then return end
		
		SF.Editor.editor = vgui.Create("Expression2EditorFrame")

		-- Change default event registration so we can have custom animations for starfall
		function SF.Editor.editor:SetV(bool)
			local wire_expression2_editor_worldclicker = GetConVar("wire_expression2_editor_worldclicker")

			if bool then
				self:MakePopup()
				self:InvalidateLayout(true)
				if self.E2 then self:Validate() end
			end
			self:SetVisible(bool)
			self:SetKeyBoardInputEnabled(bool)
			self:GetParent():SetWorldClicker(wire_expression2_editor_worldclicker:GetBool() and bool) -- Enable this on the background so we can update E2's without closing the editor
			if CanRunConsoleCommand() then
				RunConsoleCommand("starfall_event", bool and "editor_open" or "editor_close")
			end
		end

		function SF.Editor.editor:SaveFile( Line, close, SaveAs )
			self:ExtractName( )
			if close and self.chip then
				if not self:Validate( true ) then return end
				net.Start( "starfall_uploadandexit" )
					net.WriteEntity( self.chip ) 
				net.SendToServer( )
				self:Close( )
				return
			end
			if not Line or SaveAs or Line == self.Location .. "/" .. ".txt" then
				local str
				if self.C[ 'Browser' ].panel.File then
					str = self.C[ 'Browser' ].panel.File.FileDir -- Get FileDir
					if str and str ~= "" then -- Check if not nil
						-- Remove "expression2/" or "cpuchip/" etc
						local n, _ = str:find( "/", 1, true )
						str = str:sub( n + 1, -1 )

						if str and str ~= "" then -- Check if not nil
							if str:Right( 4 ) == ".txt" then -- If it's a file
								str = string.GetPathFromFilename( str ):Left( -2 ) -- Get the file path instead
								if not str or str == "" then
									str = nil
								end
							end
						else
							str = nil
						end
					else
						str = nil
					end
				end
				Derma_StringRequestNoBlur( "Save to New File", "", ( str ~= nil and str .. "/" or "" ) .. self.savefilefn,
					function( strTextOut )
						strTextOut = string.gsub( strTextOut, ".", invalid_filename_chars )
						self:SaveFile( self.Location .. "/" .. strTextOut .. ".txt", close )
					end )
				return
			end

			file.Write( Line, self:GetCode( ) )

			local panel = self.C[ 'Val' ].panel
			timer.Simple( 0, function( ) panel.SetText( panel, "   Saved as " .. Line ) end )

			if not self.chip then self:ChosenFile( Line ) end
			if close then
				SF.AddNotify( LocalPlayer(), "Starfall code saved as " .. Line .. ".", NOTIFY_GENERIC, 7, NOTIFYSOUND_DRIP3 )
				self:Close( )
			end
		end

		SF.Editor.editor:Setup("SF Editor", "starfall", "nothing") -- Setting the editor type to not nil keeps the validator line
		
		if not file.Exists("starfall", "DATA") then
			file.CreateDir("starfall")
		end
		
		-- Add "Sound Browser" button
		do
			local editor = SF.Editor.editor
			local SoundBrw = editor:addComponent(vgui.Create("Button", editor), -205, 30, -125, 20)
			SoundBrw.panel:SetText("")
			SoundBrw.panel.Font = "E2SmallFont"
			SoundBrw.panel.Paint = function(button)
				local w,h = button:GetSize()
				draw.RoundedBox(1, 0, 0, w, h, editor.colors.col_FL)
				if ( button.Hovered ) then draw.RoundedBox(0, 1, 1, w - 2, h - 2, Color(0,0,0,192)) end
				surface.SetFont(button.Font)
				surface.SetTextPos( 3, 4 )
				surface.SetTextColor( 255, 255, 255, 255 )
				surface.DrawText("  Sound Browser")
			end
			SoundBrw.panel.DoClick = function() RunConsoleCommand("wire_sound_browser_open") end
			editor.C.SoundBrw = SoundBrw
		end
		
		-- Add "SFHelper" button
		do
			local editor = SF.Editor.editor
			local SFHelp = editor:addComponent( vgui.Create( "Button" , editor ), -262, 30, -207, 20 )
			SFHelp.panel:SetText( "" )
			SFHelp.panel.Font = "E2SmallFont"
			SFHelp.panel.Paint = function ( button )
				local w, h = button:GetSize( )
				draw.RoundedBox( 1, 0, 0, w, h, editor.colors.col_FL )
				if button.Hovered then 
					draw.RoundedBox( 0, 1, 1, w - 2, h - 2, Color(0, 0, 0, 192) ) 
				end
				surface.SetFont( button.Font )
				surface.SetTextPos( 3, 4 )
				surface.SetTextColor( 255, 255, 255, 255 )
				surface.DrawText( "  SFHelper" )
			end
			SFHelp.panel.DoClick = function ( )
				SF.Helper.show( )
			end
			editor.C.SFHelp = SFHelp
		end
		
		SF.Editor.editor:SetSyntaxColorLine( SyntaxColorLine )
		--SF.Editor.editor:SetSyntaxColorLine( function(self, row) return {{self.Rows[row], Color(255,255,255)}} end)
		
		function SF.Editor.editor:OnTabCreated( tab )
			local editor = tab.Panel
			editor:SetText( code1 .. code2 )
			editor.Start = editor:MovePosition({1,1}, #code1)
			editor.Caret = editor:MovePosition(editor.Start, #code2)
		end
		
		local editor = SF.Editor.editor:GetCurrentEditor()
		
		function SF.Editor.editor:Validate(gotoerror)
			local err = CompileString(self:GetCode(), "SF:"..(self:GetChosenFile() or "main"), false)
			
			if type(err) == "string" then
				self.C['Val'].panel:SetBGColor(128, 0, 0, 180)
				self.C['Val'].panel:SetFGColor(255, 255, 255, 128)
				self.C['Val'].panel:SetText( "   " .. err )
			else
				self.C['Val'].panel:SetBGColor(0, 128, 0, 180)
				self.C['Val'].panel:SetFGColor(255, 255, 255, 128)
				self.C['Val'].panel:SetText( "   No Syntax Errors" )
			end
			return true
		end
	end
	
	--- (Client) Returns true if initialized
	function SF.Editor.isInitialized()
		return SF.Editor.editor and true or false
	end
	
	--- (Client) Opens the editor. Initializes it first if needed.
	function SF.Editor.open()
		SF.Editor.init()
		SF.Editor.editor:Open()
	end
	
	--- (Client) Gets the filename of the currently selected file.
	-- @return The open file or nil if no files opened or not initialized
	function SF.Editor.getOpenFile()
		if not SF.Editor.editor then return nil end
		return SF.Editor.editor:GetChosenFile()
	end
	
	--- (Client) Gets the current code inside of the editor
	-- @return Code string or nil if not initialized
	function SF.Editor.getCode()
		if not SF.Editor.editor then return nil end
		return SF.Editor.editor:GetCode()
	end
	
	--- (Client) Builds a table for the compiler to use
	-- @param maincode The source code for the main chunk
	-- @param codename The name of the main chunk
	-- @return True if ok, false if a file was missing
	-- @return A table with mainfile = codename and files = a table of filenames and their contents, or the missing file path.
	function SF.Editor.BuildIncludesTable(maincode, codename)

		local currentEditor = SF.Editor.editor:GetCurrentEditor()
		local currentIncludes = nil
		if not ( maincode or codename ) then
			currentIncludes = currentEditor.includes
		end
		if currentIncludes then
			local list = currentEditor.includeswindow.list
			currentEditor.includes[ list:GetLine( list:GetSelectedLine() ):GetColumnText( 1 ) ] = currentEditor:GetValue()
		end

		local tbl = {}
		maincode = maincode or ( currentIncludes and currentIncludes[ currentEditor.mainfile ] ) or SF.Editor.getCode()
		codename = codename or ( currentIncludes and currentEditor.mainfile ) or SF.Editor.getOpenFile() or "main"
		tbl.mainfile = codename
		tbl.files = {}
		tbl.filecount = 0
		tbl.includes = {}

		local loaded = {}
		local ppdata = {}

		local function recursiveLoad(path)
			if loaded[path] then return end
			loaded[path] = true
			
			local code
			if path == codename and maincode then
				code = maincode
			elseif currentIncludes and currentIncludes[path] then
				code = currentIncludes[path]
			else
				code = file.Read("Starfall/"..path, "DATA") or error("Bad include: "..path,0)
			end
			
			tbl.files[path] = code
			SF.Preprocessor.ParseDirectives(path,code,{},ppdata)
			
			if ppdata.includes and ppdata.includes[path] then
				local inc = ppdata.includes[path]
				if not tbl.includes[path] then
					tbl.includes[path] = inc
					tbl.filecount = tbl.filecount + 1
				else
					assert(tbl.includes[path] == inc)
				end
				
				for i=1,#inc do
					recursiveLoad(inc[i])
				end
			end
		end
		local ok, msg = pcall(recursiveLoad, codename)
		if ok then
			return true, tbl
		elseif msg:sub(1,13) == "Bad include: " then
			return false, msg
		else
			error(msg,0)
		end
	end

	net.Receive( "starfall_download", function( len )
		local ent = net.ReadEntity()
		SF.Editor.editor.chip = ent
		local mainfile = net.ReadTable()[1]
		local files = net.ReadTable()
		local editor = SF.Editor.editor

		local function tableEquals( t1, t2 )
			if not t1 or not t2 then return end
			for k, v in pairs( t1 ) do
				if not t2[k] or v ~= t2[k] then
					return false
				end
			end
			for k, v in pairs( t2 ) do
				if not t1[k] or v ~= t1[k] then
					return false
				end
			end
			return true
		end

		local currentFile = nil
		local currentCode = nil
		local index = nil
		for i = 1, editor:GetNumTabs() do
			if editor:GetEditor(i):GetValue() == files[ mainfile ] then
				currentFile = mainfile
				curreentCode = editor:GetEditor( i ):GetValue()
				index = i
				break
			end
		end

		if currentFile then
			local ok, currentFiles = SF.Editor.BuildIncludesTable( currentCode, currentFile )
			currentFiles = currentFiles.files
			if ok and tableEquals( currentFiles, files ) then
				editor:SetActiveTab( index )
				return
			end
		end

		for i = 1, editor:GetNumTabs( ) do
			if tableEquals( editor:GetEditor( i ).includes, files ) then
				editor:SetActiveTab( i )
				return
			end
		end

		editor:Open( mainfile, files[ mainfile ], true )
		local currentEditor = SF.Editor.editor:GetCurrentEditor()
		createIncludesWindow( currentEditor )
		currentEditor.includeswindow:Update( mainfile, files, ent )
	end )

	-- CLIENT ANIMATION

	local busy_players = {}
	hook.Add("EntityRemoved", "starfall_busy_animation", function(ply)
		busy_players[ply] = nil
	end)

	local emitter = ParticleEmitter(vector_origin)

	net.Receive("starfall_editor_status", function(len)
		local ply = net.ReadEntity()
		local status = net.ReadBit() ~= 0 -- net.ReadBit returns 0 or 1, despite net.WriteBit taking a boolean
		if not ply:IsValid() or ply == LocalPlayer() then return end

		busy_players[ply] = status or nil
	end)

	local rolldelta = math.rad(80)
	timer.Create("starfall_editor_status", 1/3, 0, function()
		rolldelta = -rolldelta
		for ply, _ in pairs(busy_players) do
			local BoneIndx = ply:LookupBone("ValveBiped.Bip01_Head1") or ply:LookupBone("ValveBiped.HC_Head_Bone") or 0
			local BonePos, BoneAng = ply:GetBonePosition(BoneIndx)
			local particle = emitter:Add("radon/starfall2", BonePos + Vector(math.random(-10,10), math.random(-10,10), 60+math.random(0,10)))
			if particle then
				particle:SetColor(math.random(30,50),math.random(40,150),math.random(180,220) )
				particle:SetVelocity(Vector(0, 0, -40))

				particle:SetDieTime(1.5)
				particle:SetLifeTime(0)

				particle:SetStartSize(10)
				particle:SetEndSize(5)

				particle:SetStartAlpha(255)
				particle:SetEndAlpha(0)

				particle:SetRollDelta(rolldelta)
			end
		end
	end)

	-- INCLUDES WINDOW

	function createIncludesWindow( editor )
		editor.includeswindow = vgui.Create( "DPanel", editor )
		editor.includeswindow:SetPos( SF.Editor.editor:GetWide()-236-150, 50 )
		editor.includeswindow:SetSize( 150, 200 )
		local r, g, b = GetConVar("wire_expression2_editor_color_fl"):GetString():match("(%d+)_(%d+)_(%d+)")
		editor.includeswindow:SetBackgroundColor(Color(tonumber(r),tonumber(g),tonumber(b)))
		editor.includeswindow.open = true

		local window = editor.includeswindow

		local posx, posy = window:GetPos()
		window.button = vgui.Create( "DImageButton", editor )
		window.button:SetPos( posx-32, posy+68 )
		window.button:SetImage( "radon/next.png" )
		window.button:SizeToContents()
		window.button.state = "next"
		window.button.DoClick = function()
			window.startx = window:GetPos()
			hook.Add( "Think", "AnimateIncludes", function()
				local xpos = window:GetPos()
				if window.open then
					if window.button.state == "next" then
						window.button:SetImage( "radon/last.png" )
						window.button.state = "last"
					end
					window:SetPos( xpos + 2, 50 )
					if ( xpos + 2 ) - window.startx == 150 then
						hook.Remove( "Think", "AnimateIncludes" )
						window.open = false
						window.startx = window:GetPos()
					end
				else
					if window.button.state == "last" then
						window.button:SetImage( "radon/next.png" )
						window.button.state = "next"
					end
					window:SetPos( xpos - 2, 50 )
					if window.startx - ( xpos - 2 ) == 150 then
						hook.Remove( "Think", "AnimateIncludes" )
						window.open = true
						window.startx = window:GetPos()
					end
				end
			end )
		end
		local lastw, lasth = SF.Editor.editor:GetSize()
		window.Think = function()
			local w, h = SF.Editor.editor:GetSize()
			local changew, changeh = w - lastw, h - lasth
			window:SetPos( window:GetPos()+changew, 50 )
			window.button:SetPos( window:GetPos()-32, 118 )
			lastw, lasth = w, h
		end
		function window:Update( mainfile, files, ent )
			editor.includes = files
			editor.mainfile = mainfile
			editor.chosenfile = mainfile--tostring( ent )

			self.list:Clear()
			local function reverseTable( tbl ) 
				local r = {}
				for k, v in pairs( tbl ) do
					table.insert( r, 1, k )
				end
				return r
			end			
			local filesToAdd = reverseTable( files )
			for k, v in pairs( filesToAdd ) do
				self.list:AddLine( v )
			end
			self.list:SelectFirstItem()
		end

		window.list = vgui.Create( "DListView", window )
		window.list:SetMultiSelect( false )
		window.list:AddColumn( "Files" )
		window.list:SetPos( 6, 6 )
		window.list:SetSize( 138, 161 )
		function window.list:OnRowSelected( index, row )
			local file = row:GetColumnText(1)
			editor.includes[ editor.chosenfile ] = editor:GetValue()
			editor.chosenfile = file
			editor:SetText( editor.includes[ file ] )
		end

		window.savebutton = vgui.Create( "DButton", window )
		window.savebutton:SetPos( 6, 172 )
		window.savebutton:SetSize( 138, 22 )
		window.savebutton:SetText( "Save files" )
		window.savebutton.DoClick = function()
			editor.includes[ window.list:GetLine( window.list:GetSelectedLine() ):GetColumnText( 1 ) ] = editor:GetValue()
			for k, v in pairs( editor.includes ) do
				if k == editor.mainfile then
					file.Write( k, v )
				else
					file.Write( SF.Editor.editor.Location .. "/" .. k, v )
				end
			end
			local panel = SF.Editor.editor.C[ 'Val' ].panel
			timer.Simple( 0, function( ) panel.SetText( panel, "   Files saved" ) end )
		end
	end

else

	-- SERVER STUFF HERE
	-- -------------- client-side event handling ------------------
	-- this might fit better elsewhere

	util.AddNetworkString("starfall_editor_status")
	util.AddNetworkString("starfall_uploadandexit")
	util.AddNetworkString("starfall_download")

	resource.AddFile( "materials/radon/starfall2.png" )
	resource.AddFile( "materials/radon/starfall2.vmt" )
	resource.AddFile( "materials/radon/starfall2.vtf" )
	resource.AddFile( "materials/radon/next.png" )
	resource.AddFile( "materials/radon/last.png" )

	local starfall_event = {}


	concommand.Add("starfall_event", function(ply, command, args)
		local handler = starfall_event[args[1]]
		if not handler then return end
		return handler(ply, args)
	end)


	-- actual editor open/close handlers


	function starfall_event.editor_open(ply, args)
		net.Start("starfall_editor_status")
		net.WriteEntity(ply)
		net.WriteBit(true)
		net.Broadcast()
	end


	function starfall_event.editor_close(ply, args)
		net.Start("starfall_editor_status")
		net.WriteEntity(ply)
		net.WriteBit(false)
		net.Broadcast()
	end

	net.Receive( "starfall_uploadandexit", function( len, ply ) 
		ent = net.ReadEntity()
			
		--Check cppi or ownership again incase someone manually changes SF.Editor.editor.chip or permissions change
		if ( CPPI and not ent:CPPICanTool( ply, ent:GetClass() ) ) or ( not CPPI and ply ~= ent.owner ) then 
			SF.AddNotify( ply, "Cannot upload SF code, permission denied", NOTIFY_ERROR, 7, NOTIFYSOUND_ERROR1 )
			return 
		end

		if not SF.RequestCode( ply, function( mainfile, files )
			if not mainfile then return end
			if not IsValid( ent ) then return end

			if ent:GetClass() == "starfall_processor" then
				ent:Compile( files, mainfile )
			else
				ent:CodeSent( ply, files, mainfile )
			end
		end ) then
			SF.AddNotify( ply, "Cannot upload SF code, please wait for the current upload to finish.", NOTIFY_ERROR, 7, NOTIFYSOUND_ERROR1 )
		end
	end )

end
