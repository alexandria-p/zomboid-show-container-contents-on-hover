print("ShowContainerContentsOnHover Mod loaded successfully")

---------------------------------------------
-- Alex ISInventoryPage (adds checkbox)
---------------------------------------------
local vanilla_createChildren = ISInventoryPage.createChildren
function ISInventoryPage:createChildren()
    vanilla_createChildren(self)

    local titleBarHeight = self:titleBarHeight()
    self.tickBox = ISTickBox:new(0, 0, titleBarHeight - 5, titleBarHeight - 5, "", self, self.onHoverShowContainerContentsTicked)
    self.tickBox:initialise();
    self.tickBox:instantiate();
    self:addChild(self.tickBox)
    self.tickBox:addOption("Hover to show contents");
    self.tickBox:setVisible(false)
    self.tickBox.selected[1] = false;

    self.overrideTickBox = ISTickBox:new(0, 0, titleBarHeight - 5, titleBarHeight - 5, "", self, self.onOverrideShowContainerContentsTicked)
    self.overrideTickBox:initialise();
    self.overrideTickBox:instantiate();
    self:addChild(self.overrideTickBox)
    self.overrideTickBox:addOption("Override - contents hover");
    self.overrideTickBox:setVisible(false)
    self.overrideTickBox.selected[1] = false;
end


local vanilla_prerender = ISInventoryPage.prerender
function ISInventoryPage:prerender()

    self.tickBox.selected[1] = false
    self.overrideTickBox.selected[1] = false

    -- prefill checkbox (if necessary)
    if self.tickBox and self.inventory:getParent() then
        local modData = self.inventory:getParent():getModData()
        if modData.DisplayContainerContents_ShowPanel and modData.DisplayContainerContents_ShowPanel == 1 then
            self.tickBox.selected[1] = true
        end
    end

    if self.overrideTickBox and self.onCharacter and self.inventory:getParent() then
        local modData = self.inventory:getParent():getModData()
        if modData.DisplayContainerContents_OverrideShowPanel and modData.DisplayContainerContents_OverrideShowPanel == 1 then
            self.overrideTickBox.selected[1] = true
        end
    end
    
    vanilla_prerender(self)

    if self.tickBox and not self.onCharacter and self.inventory:getType() ~= "floor" and self.inventory:getParent() then
        self.tickBox:setVisible(true)

        local tickBoxX = GetCheckboxXPositionForContainerInventory(self)
        
        self.tickBox:setX(tickBoxX)
    else
        self.tickBox:setVisible(false)
    end

    if self.overrideTickBox and self.onCharacter and self.inventory:getParent() then
        self.overrideTickBox:setVisible(true)

        local overrideTickBoxX = GetCheckboxXPositionForPlayerInventory(self)

        self.overrideTickBox:setX(overrideTickBoxX)
    else
        self.overrideTickBox:setVisible(false)
    end
end

function GetCheckboxXPositionForContainerInventory(inventoryPage)
    local x = 0
    local margin = 16

    -- Vanilla implementation
    -- (toggleStove/removeAll are no longer buttons on the title bar in this game
    -- version -- they moved into inventoryPage.containerButtonPanel -- so lootAll
    -- is the last real title-bar button for a container inventory page)
    x = inventoryPage.lootAll:getRight() + margin

    -- Override for mods
    if inventoryPage.searchButton and inventoryPage.searchButton:getIsVisible() then
        x = inventoryPage.searchButton:getRight() + margin
    end

    return x
end

function GetCheckboxXPositionForPlayerInventory(inventoryPage)
    local x = 0
    local margin = 16

    -- Vanilla implementation
    local invX = inventoryPage.infoButton:getRight() + 1
    local invNameLength = getTextManager():MeasureStringX(inventoryPage.font, inventoryPage.title)

    x = invX + invNameLength + margin

    -- Override for mods
    if inventoryPage.searchButton and inventoryPage.searchButton:getIsVisible() then
        x = inventoryPage.searchButton:getRight() + margin
    end

    return x
end



function ISInventoryPage:onHoverShowContainerContentsTicked(index, selected)
    local wasTicked = 0

    if selected then
        wasTicked = 1
    end

    self.inventory:getParent():getModData().DisplayContainerContents_ShowPanel = wasTicked -- will be 1 or 0
    self.inventory:getParent():transmitModData()
end

function ISInventoryPage:onOverrideShowContainerContentsTicked(index, selected)
    local wasTicked = 0

    if selected then
        wasTicked = 1
    end

    self.inventory:getParent():getModData().DisplayContainerContents_OverrideShowPanel = wasTicked -- will be 1 or 0
    self.inventory:getParent():transmitModData()
end

---------------------------------------------
-- Alex panel class
---------------------------------------------

DerivedPanel = ISPanel:derive("DerivedPanel")

PanelClass = {}


-- Setup variables for rendering item textures
xIndent = 10
yIndent = 10
        
texW = 32
texH = 32

function PanelClass:Create()
    local this = 
    {
        internalPanel = nil,
        containerObjectId = 0,
        containerName = "",
        items = {},
    }

    function this:setup(x, y, width, height, conId, conName, its)
        self.containerObjectId = conId
        self.containerName = conName
        self.items = its
        self.internalPanel = DerivedPanel:new(x, y, width, height)
    end

    function this:showPanel()
        self.internalPanel:setVisible(true)
        self.internalPanel:addToUIManager()
    end

    function this:hidePanel()
        self.internalPanel:setVisible(false)
        self.internalPanel:removeFromUIManager()
    end

    function this:runMyRender()
        DerivedPanel:render(self.internalPanel)

        -- Render name of container at the top
        self.internalPanel:drawTextCentre(
            self.containerName,
            self.internalPanel.width  /  2,
            5,
            1, 1, 1, 1,
            UIFont.Medium
        )

        -- resize panel (if necessary) to dynamically accomodate to contents
        -- this function also draws our item textures :)
        local panelHeight = GetPanelHeight(self.items, self.internalPanel.width, self.internalPanel, true)
        self.internalPanel:setHeight(panelHeight)
    end

-- Getters

    function this:getContainerName()
        return self.containerName
    end

    function this:getContainerObjectId()
        return self.containerObjectId
    end

    function this:getPanel()
        return self.internalPanel
    end

    function this:getItems()
        return self.items
    end

    function this:setContainerName(conName)
        self.containerName = conName
    end

    function this:setItems(its)
        self.items = its
    end

    return this
end

---------------------------------------------
-- Alex mod logic
---------------------------------------------

-- containerObjectId -> panelObject, for O(1) exists/insert/remove
PanelByContainerId = {}

-- squareId (string) -> array of panelObjects on that square, for O(1)-ish per-square lookups
PanelsBySquare = {}

function GetPanelHeight(items, panelWidth, optionalPanelRef, drawTextures)
    -- do not draw repeated textures (set: texture -> true, O(1) lookup)
    local drawnTextures = {}

    local containerNameHeight = getTextManager():MeasureStringY(UIFont.Medium, "dummy text")

    local iconYOffset = containerNameHeight + yIndent/2

    local maxWidth = panelWidth - (xIndent * 2)

    local row = 1
    local column = 1

    local maxRow = 1
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        local texture = item:getTexture()

        if not drawnTextures[texture] then
            drawnTextures[texture] = true

            currentWidth = (xIndent + (column - 1) * texW) + texW -- starting x + texW = ending x of texture on screen

            if currentWidth >= maxWidth then
                row = row + 1
                column = 1
            end

            if drawTextures and optionalPanelRef ~= nil then
                optionalPanelRef:drawTextureScaled(texture, xIndent + (column - 1) * texW, iconYOffset + yIndent + (row - 1) * texH, texW, texH, 1.0, 1.0, 1.0, 1.0)
            end

            maxRow = math.max(maxRow, row)

            column = column + 1
        end
    end

    -- resize panel (if necessary) to dynamically accomodate to contents
    if items:size() > 0 then
        return iconYOffset + yIndent + maxRow * texH + yIndent
    else
        return containerNameHeight + yIndent*2
    end
end

function ExistsInPanelList(containerObjectId)
    return PanelByContainerId[containerObjectId]
end

function GetXOffset(squareId, numOfContainerOnSquare)

    if (squareId % 2 ~= 0) then
        return 0
    end

    -- add an indent for every second panel
    local panelsOnSquare = PanelsBySquare[squareId:toString()]
    if panelsOnSquare == nil then
        return 0
    end

    return #panelsOnSquare * 15
end

function GetYOffset(squareId, numOfContainerOnSquare)
    local yMargin = 15

    if numOfContainerOnSquare == 0 then
        return 0
    end

    if numOfContainerOnSquare == 1 then
        return yMargin
    end

    local squareIdStr = squareId:toString()
    local panelsOnSquare = PanelsBySquare[squareIdStr]
    local returnOffset = 0

    if panelsOnSquare ~= nil then
        for i=1,#panelsOnSquare do
            local currentPanel = panelsOnSquare[i]

            -- don't add the height of the first panel to the offset
            if currentPanel:getContainerObjectId() ~= squareIdStr .. "_0" then
                returnOffset = returnOffset + currentPanel:getPanel().height
            end
        end
    end

    -- add a margin
    returnOffset = returnOffset + (yMargin * numOfContainerOnSquare)

    return returnOffset
end

-- Function to create the tooltip text with preview icons of the container's contents.
local function CreateUpdateContainerTooltip(container, containerObjectId, containerName, containerObject, squareId, numOfContainerOnSquare)

    local items = container:getItems() 

    -- get panel, if exists
    -- then do nothing & return early
    local existingPanel = ExistsInPanelList(containerObjectId)
    if existingPanel ~= nil then
        -- refresh the items in the list & the container name
        existingPanel:setContainerName(containerName)
        existingPanel:setItems(items)
        return
    end

    -- OR create new one

    -- Create the tooltip text using the container's name and description.
    local tooltip = containerName .. "\n\n"
   
    -- Initialise panel at the container's IsoObject x/y SCREEN coordinates
    local myPanelWidth = getCore():getScreenWidth() / 10
    local myPanelHeight = GetPanelHeight(items, myPanelWidth, nil, false)

    local sX, sY = ISCoordConversion.ToScreen(containerObject:getX(), containerObject:getY(), containerObject:getZ())
    sX = math.floor( sX )
    sY = math.floor( sY )

    local dynamicOffset = GetYOffset(squareId, numOfContainerOnSquare)

    if (numOfContainerOnSquare > 0) then
        dynamicOffset = dynamicOffset + myPanelHeight
    end

    sY = sY - dynamicOffset;

    if (numOfContainerOnSquare > 0) then
        sX = sX + (numOfContainerOnSquare * GetXOffset(squareId, numOfContainerOnSquare)) -- adds a little stepped indent
    end

    -- Create new panel
    local panelObject = PanelClass:Create()
    panelObject:setup(sX, sY, myPanelWidth, myPanelHeight, containerObjectId, containerName, items)

    local internalPanel = panelObject:getPanel()

    -- setup render overrides (closure captures panelObject directly, no lookup needed)
    function internalPanel:render()
        panelObject:runMyRender()
    end

    -- Display panel
    PanelByContainerId[containerObjectId] = panelObject

    local squareIdStr = squareId:toString()
    local panelsOnSquare = PanelsBySquare[squareIdStr]
    if panelsOnSquare == nil then
        panelsOnSquare = {}
        PanelsBySquare[squareIdStr] = panelsOnSquare
    end
    table.insert(panelsOnSquare, panelObject)

    panelObject:showPanel()

end

-- We'll use this event to display a tooltip for the container.
function ObjectContextMenu(x, y, xMultiplied, yMultiplied)
    --print("on hover")

    -- List of container found Ids.
    local foundContainerObjectIds = {}

    -- Get coordinates
    local hoveredSquare
    local squareId

    -- get the cell
    local cell = getWorld():getCell();

    local player = getPlayer()
    local playerSquare = player:getSquare()
    local playerSquareZ = 0

    if playerSquare ~= nil then
        playerSquareZ = playerSquare:getZ()
    end

    local mX, mY = ISCoordConversion.ToWorld(x, y, player:getZ())
    mX = math.floor( mX )
    mY = math.floor( mY )

    -- return squares for the same level that the player is on
    hoveredSquare = cell:getGridSquare(mX, mY, playerSquareZ)

    if hoveredSquare ~= nil then
        squareId = hoveredSquare:getID()
        local squareObjects = hoveredSquare:getObjects()

        local containersFoundOnSquare = 0

        for i=0, squareObjects:size()-1 do 
            local currentObj = squareObjects:get(i)

            if currentObj:getContainer() then
                local modData = currentObj:getModData()

                local container = currentObj:getContainer()
                local containerName = container:getType()
                local containerObjectId = squareId:toString() .. "_" .. containersFoundOnSquare

                -- check if container name should be overwritten by RenameContainers mod
                if modData.RenameContainer_CustomName and modData.RenameContainer_CustomName ~= "" then
                    containerName = modData.RenameContainer_CustomName
                end

                -- first letter to uppercase
                containerName = firstToUpper(containerName)

                -- print(containerName)
                local playerInventoryObject = player:getInventory():getParent()
                local playerModData = playerInventoryObject:getModData()

                if playerModData.DisplayContainerContents_OverrideShowPanel and playerModData.DisplayContainerContents_OverrideShowPanel == 1 then
                    table.insert(foundContainerObjectIds, containerObjectId)
                    CreateUpdateContainerTooltip(container, containerObjectId, containerName, currentObj, squareId, containersFoundOnSquare)
                    containersFoundOnSquare = containersFoundOnSquare + 1
                elseif modData.DisplayContainerContents_ShowPanel and modData.DisplayContainerContents_ShowPanel == 1 then
                    table.insert(foundContainerObjectIds, containerObjectId)
                    CreateUpdateContainerTooltip(container, containerObjectId, containerName, currentObj, squareId, containersFoundOnSquare)
                    containersFoundOnSquare = containersFoundOnSquare + 1
                end
            end
        end
    end

    if hoveredSquare == nil then
        -- clear all panels
        for containerId, panel in pairs(PanelByContainerId) do
            panel:hidePanel()
        end
        PanelByContainerId = {}
        PanelsBySquare = {}
    else
        -- hide & delete all entries for every square other than the one we're hovering
        local squareIdStr = squareId:toString()
        for sqId, panelsOnSquare in pairs(PanelsBySquare) do
            if sqId ~= squareIdStr then
                for i=1,#panelsOnSquare do
                    local currentPanel = panelsOnSquare[i]
                    currentPanel:hidePanel()
                    PanelByContainerId[currentPanel:getContainerObjectId()] = nil
                end
                PanelsBySquare[sqId] = nil
            end
        end
    end
end

function firstToUpper(str)
    return (str:gsub("^%l", string.upper))
end

-- Register our event handler function.
Events.OnMouseMove.Add(ObjectContextMenu)