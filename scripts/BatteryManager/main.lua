-- Ethos Battery Manager
local debug = false

local HapticPatterns = {{". . . . . .", 1}, {". - . - . - .", 2}, {". - - . - - . - - . - - .", 3}}

-- Get Radio Version to determine field size
local radio = system.getVersion()

local jsonFile = assert(loadfile("lib/json_file.lua"))()

local function readFromFiles(widget)
    if os.stat("batteries.json") then
        widget.batteries = jsonFile.load("batteries.json")
    end
    if not widget.batteriesLoaded then
        widget.batteriesLoaded = true
    end
end
-- This function is called when the widget is first created
local function create()
    local widget = {
        batteriesLoaded = false,

        sensors = {
            remaining = nil,

            consumption = nil,
            lastConsumptionSensorUpdateTime = 0,
            cellCount = nil,
            voltage = nil,
            modelId = nil
        },

        -- Form Panels
        panels = {
            batteries = nil,
            settings = nil,
            sensors = nil
        },

        -- Battery Handling
        batteries = {},

        config = {
            useCapacity = 70,
            voltageCheckEnabled = false,
            voltageCheckMinChargedCellVoltage = 415,
            voltageCheckHapticEnabled = false,
            voltageCheckHapticPattern = nil,
            remainingCalloutSwitch = nil,
            remainingCalloutInterval = 10,
            remainingCalloutZeroPercentInterval = 5,
            remainingCalloutHapticEnabled = false,
            remainingCalloutHapticPattern = nil,
            pinnedModelId = 0,

            consumptionSensor = nil,
            cellCountSensor = nil,
            voltageSensor = nil,
            modelIdSensor = nil
        },

        -- Widget Runtime
        runtime = {
            selectedModelBattery = nil,
            lastReconcileTime = os.clock(),
            telemetryActive = false,
            telemetryActiveTime = nil,
            widgetRebuildRequired = false,
            batteryChoiceFieldFocusOnBuild = false,

            -- Model ID
            modelId = {
                last = nil,
                current = nil
            },
            -- Voltage Check
            voltageCheck = {
                completed = false,
                promptOpen = false,
                lastCheckTime = nil,
                batteryConnectTime = nil
            },
            -- Alerts
            alerts = {
                noBatteries = {
                    enabled = false,
                    lastPlayTime = nil
                },
                selectBattery = {
                    enabled = false,
                    lastPlayTime = nil
                },
                percentageRemaining = {
                    lastPercentage = nil,
                    lastCriticalPlayTime = nil
                }
            }
        }
    }
    readFromFiles(widget)
    return widget
end

local function read(widget)
    readFromFiles(widget)

    widget.config.pinnedModelId = storage.read("m0")
    widget.config.useCapacity = storage.read("m1")
    storage.read("m2") -- reserved for future use
    storage.read("m3") -- reserved for future use
    storage.read("m4") -- reserved for future use
    widget.config.voltageCheckEnabled = storage.read("m5")
    widget.config.voltageCheckMinChargedCellVoltage = storage.read("m6")
    widget.config.voltageCheckHapticEnabled = storage.read("m7")
    widget.config.voltageCheckHapticPattern = storage.read("m8")
    storage.read("m9") -- reserved for future use
    storage.read("m10") -- reserved for future use
    storage.read("m11") -- reserved for future use
    storage.read("m12") -- reserved for future use
    storage.read("m13") -- reserved for future use
    storage.read("m14") -- reserved for future use
    widget.config.remainingCalloutSwitch = storage.read("m15")
    widget.config.remainingCalloutInterval = storage.read("m16")
    widget.config.remainingCalloutZeroPercentInterval = storage.read("m17")
    widget.config.remainingCalloutHapticEnabled = storage.read("m18")
    widget.config.remainingCalloutHapticPattern = storage.read("m19")
    widget.config.consumptionSensor = storage.read("m20")
    widget.config.cellCountSensor = storage.read("m21")
    widget.config.voltageSensor = storage.read("m22")
    widget.config.modelIdSensor = storage.read("m23")
end

local function writeToFiles(widget)
    if widget.batteries and widget.batteriesLoaded then
        jsonFile.save("batteries.json", widget.batteries)
    end
end

local function write(widget)
    writeToFiles(widget)
    storage.write("m0", widget.config.pinnedModelId)
    storage.write("m1", widget.config.useCapacity)
    storage.write("m2", "") -- reserved for future use
    storage.write("m3", "") -- reserved for future use
    storage.write("m4", "") -- reserved for future use
    storage.write("m5", widget.config.voltageCheckEnabled)
    storage.write("m6", widget.config.voltageCheckMinChargedCellVoltage)
    storage.write("m7", widget.config.voltageCheckHapticEnabled)
    storage.write("m8", widget.config.voltageCheckHapticPattern)
    storage.write("m9", "") -- reserved for future use
    storage.write("m10", "") -- reserved for future use
    storage.write("m11", "") -- reserved for future use
    storage.write("m12", "") -- reserved for future use
    storage.write("m13", "") -- reserved for future use
    storage.write("m14", "") -- reserved for future use
    storage.write("m15", widget.config.remainingCalloutSwitch)
    storage.write("m16", widget.config.remainingCalloutInterval)
    storage.write("m17", widget.config.remainingCalloutZeroPercentInterval)
    storage.write("m18", widget.config.remainingCalloutHapticEnabled)
    storage.write("m19", widget.config.remainingCalloutHapticPattern)
    storage.write("m20", widget.config.consumptionSensor)
    storage.write("m21", widget.config.cellCountSensor)
    storage.write("m22", widget.config.voltageSensor)
    storage.write("m23", widget.config.modelIdSensor)
end

local function requestWidgetRebuild(widget)
    widget.runtime.widgetRebuildRequired = true
end

local function resetBatteryVoltageCheck(widget, completed)
    widget.runtime.voltageCheck.completed = completed

    widget.runtime.voltageCheck.lastCheckTime = nil
    widget.runtime.voltageCheck.batteryConnectTime = nil
end

local function fillBatteryPanel(widget)
    if not widget.panels.batteries then
        return
    else
        widget.panels.batteries:clear()
    end

    local field
    -- Create header for the battery panel
    local line = widget.panels.batteries:addLine("")

    local w, h = lcd.getWindowSize()

    local offsetX = 0
    local optionsButtonWidth = lcd.getTextSize("...") + 16
    local addButtonWidth = lcd.getTextSize("Add New") + 16
    local batteryLineWidth = w - offsetX - optionsButtonWidth - 32
    local header1Width = math.floor(batteryLineWidth * (.65) + .5) -- name
    local header2Width = math.floor(batteryLineWidth * (.075) + .5) -- cell count 
    local header3Width = math.floor(batteryLineWidth * (.2) + .5) -- capacity 
    local header4Width = math.floor(batteryLineWidth * (.075) + .5) -- model ID

    local wOfName, hOfName = lcd.getTextSize("Name")
    local headerHeight = hOfName + 16
    local headerY = (headerHeight - hOfName) / 2
    form.addStaticText(line, {
        x = offsetX,
        y = headerY,
        w = header1Width,
        h = headerHeight
    }, "Name")
    form.addStaticText(line, {
        x = offsetX + header1Width,
        y = headerY,
        w = header2Width,
        h = headerHeight
    }, "Cells")
    form.addStaticText(line, {
        x = offsetX + header1Width + header2Width,
        y = headerY,
        w = header3Width,
        h = headerHeight
    }, "Capacity")
    form.addStaticText(line, {
        x = offsetX + header1Width + header2Width + header3Width,
        y = headerY,
        w = header4Width,
        h = headerHeight
    }, "mID")

    for i, battery in ipairs(widget.batteries) do
        line = widget.panels.batteries:addLine("")

        form.addTextField(line, {
            x = offsetX + 1,
            y = headerY,
            w = header1Width - 4,
            h = headerHeight
        }, function()
            return battery.name
        end, function(newName)
            battery.name = newName
            requestWidgetRebuild(widget)
        end)

        field = form.addNumberField(line, {
            x = offsetX + header1Width,
            y = headerY,
            w = header2Width - 4,
            h = headerHeight
        }, 0, 16, function()
            return battery.cellCount
        end, function(value)
            battery.cellCount = value
            requestWidgetRebuild(widget)
        end)
        field:enableInstantChange(false)

        field = form.addNumberField(line, {
            x = offsetX + header1Width + header2Width,
            y = headerY,
            w = header3Width - 4,
            h = headerHeight
        }, 0, 20000, function()
            return battery.capacity
        end, function(value)
            battery.capacity = value
            requestWidgetRebuild(widget)
        end)
        field:suffix("mAh")
        field:step(100)
        field:default(0)
        field:enableInstantChange(false)

        field = form.addNumberField(line, {
            x = offsetX + header1Width + header2Width + header3Width,
            y = headerY,
            w = header4Width - 4,
            h = headerHeight
        }, 0, 99, function()
            return battery.modelID
        end, function(value)
            battery.modelID = value
            requestWidgetRebuild(widget)
        end)

        field:default(0)
        field:enableInstantChange(false)

        field = form.addTextButton(line, {
            x = offsetX + header1Width + header2Width + header3Width + header4Width,
            y = headerY,
            w = optionsButtonWidth,
            h = headerHeight
        }, "...", function()
            local buttons = {{
                label = "Cancel",
                action = function()
                    return true
                end
            }, {
                label = "Delete",
                action = function()
                    table.remove(widget.batteries, i)
                    fillBatteryPanel(widget)
                    requestWidgetRebuild(widget)
                    return true
                end
            }, {
                label = "Clone",
                action = function()
                    local newBattery = {
                        name = battery.name,
                        cellCount = battery.cellCount,
                        capacity = battery.capacity,
                        modelID = battery.modelID
                    }
                    table.insert(widget.batteries, newBattery)
                    requestWidgetRebuild(widget)
                    return true
                end
            }}
            form.openDialog({
                title = (battery.name ~= "" and battery.name or "Unnamed Battery"),
                message = "Select Action",
                width = 350,
                buttons = buttons,
                options = TEXT_LEFT
            })
        end)
    end

    line = widget.panels.batteries:addLine("")
    form.addTextButton(line, {
        x = offsetX + w - addButtonWidth - 32,
        y = headerY,
        w = addButtonWidth,
        h = headerHeight
    }, "Add New", function()
        table.insert(widget.batteries, {
            name = "Battery " .. #widget.batteries + 1,
            cellCount = 0,
            capacity = 0,
            modelID = 0
        })
        fillBatteryPanel(widget)
        requestWidgetRebuild(widget)
    end)
end

local function batteryNeedsSelectionAlertActive(widget, enabled)
    if enabled then
        widget.runtime.alerts.selectBattery.enabled = true
    else
        widget.runtime.alerts.selectBattery.enabled = false
        widget.runtime.alerts.selectBattery.lastPlayTime = nil
    end
end

local function batteryNeedsSelectionAlertRun(widget, now)
    if widget.runtime.alerts.selectBattery.enabled then
        if (widget.runtime.alerts.selectBattery.lastPlayTime and now - widget.runtime.alerts.selectBattery.lastPlayTime >
            5) or not widget.runtime.alerts.selectBattery.lastPlayTime then
            system.playFile("sound/batt_needs_selection.wav")
            widget.runtime.alerts.selectBattery.lastPlayTime = now
        end
    end
end

-- Settings Panel
local function fillSettingsPanel(widget)
    if not widget.panels.settings or not widget.panels.sensors then
        return
    else
        widget.panels.settings:clear()
        widget.panels.sensors:clear()
    end

    local line = widget.panels.settings:addLine("Model ID Sensor Override")
    local field = form.addNumberField(line, nil, 0, 99, function()
        return widget.config.pinnedModelId
    end, function(value)
        widget.config.pinnedModelId = value
    end)
    field:enableInstantChange(false)

    local line = widget.panels.settings:addLine("Usable Capacity")
    local field = form.addNumberField(line, nil, 50, 100, function()
        return widget.config.useCapacity
    end, function(value)
        widget.config.useCapacity = value
    end)
    field:suffix("%")

    line = widget.panels.settings:addLine("Remaining Capacity Callout Enable")
    field = form.addSwitchField(line, nil, function()
        return widget.config.remainingCalloutSwitch
    end, function(newValue)
        widget.config.remainingCalloutSwitch = newValue
    end)

    line = widget.panels.settings:addLine("Remaining Callout Interval")
    field = form.addNumberField(line, nil, 5, 25, function()
        return widget.config.remainingCalloutInterval
    end, function(value)
        widget.config.remainingCalloutInterval = value
    end)
    field:suffix("%")

    line = widget.panels.settings:addLine("0% Remaining Repeat Interval")
    field = form.addNumberField(line, nil, 5, 60, function()
        return widget.config.remainingCalloutZeroPercentInterval
    end, function(value)
        widget.config.remainingCalloutZeroPercentInterval = value
    end)
    field:suffix("s")

    line = widget.panels.settings:addLine("0% Remaining Haptic Warning")
    form.addBooleanField(line, nil, function()
        return widget.config.remainingCalloutHapticEnabled
    end, function(newValue)
        widget.config.remainingCalloutHapticEnabled = newValue
    end)

    line = widget.panels.settings:addLine("0% Remaining Haptic Pattern")
    form.addChoiceField(line, nil, HapticPatterns, function()
        return widget.config.remainingCalloutHapticPattern
    end, function(newValue)
        widget.config.remainingCalloutHapticPattern = newValue
    end)

    -- Create field to enable/disable battery voltage checking on connect
    line = widget.panels.settings:addLine("Voltage Check Enabled")
    field = form.addBooleanField(line, nil, function()
        return widget.config.voltageCheckEnabled
    end, function(newValue)
        widget.config.voltageCheckEnabled = newValue
    end)

    line = widget.panels.settings:addLine("Min Charged Volt/Cell")
    field = form.addNumberField(line, nil, 400, 430, function()
        return widget.config.voltageCheckMinChargedCellVoltage
    end, function(value)
        widget.config.voltageCheckMinChargedCellVoltage = value
    end)
    field:decimals(2)
    field:suffix("V")

    line = widget.panels.settings:addLine("Voltage Check Haptic Warning")
    form.addBooleanField(line, nil, function()
        return widget.config.voltageCheckHapticEnabled
    end, function(newValue)
        widget.config.voltageCheckHapticEnabled = newValue
    end)

    line = widget.panels.settings:addLine("Voltage Check Haptic Pattern")
    form.addChoiceField(line, nil, HapticPatterns, function()
        return widget.config.voltageCheckHapticPattern
    end, function(newValue)
        widget.config.voltageCheckHapticPattern = newValue
    end)

    line = widget.panels.sensors:addLine("Consumption Sensor Override")
    form.addSensorField(line, nil, function()
        return widget.config.consumptionSensor
    end, function(newValue)
        widget.config.consumptionSensor = newValue
    end)

    line = widget.panels.sensors:addLine("Cell Count Sensor Override")
    form.addSensorField(line, nil, function()
        return widget.config.cellCountSensor
    end, function(newValue)
        widget.config.cellCountSensor = newValue
    end)

    line = widget.panels.sensors:addLine("Voltage Sensor Override")
    form.addSensorField(line, nil, function()
        return widget.config.voltageSensor
    end, function(newValue)
        widget.config.voltageSensor = newValue
    end)

    line = widget.panels.sensors:addLine("Model ID Sensor Override")
    form.addSensorField(line, nil, function()
        return widget.config.modelIdSensor
    end, function(newValue)
        widget.config.modelIdSensor = newValue
    end)
end

local function openBatteryVoltagePrompt(widget, title, message)
    widget.runtime.voltageCheck.promptOpen = true
    local buttons = {{
        label = "Acknowledge",
        action = function()
            widget.runtime.voltageCheck.promptOpen = false
            return true
        end
    }}
    system.playFile("sound/warning.wav")
    if widget.config.voltageCheckHapticEnabled then
        system.playHaptic(HapticPatterns[widget.config.voltageCheckHapticPattern][1])
    end
    form.openDialog({
        title = title,
        message = message,
        buttons = buttons,
        options = TEXT_LEFT
    })
end

-- Estimate cellcount and check if battery is charged.  If not, popup dialog to alert user
local function doBatteryVoltageCheck(widget)
    if not widget.runtime.telemetryActive or not widget.runtime.selectedModelBattery then -- reset the voltage check if telemetry is not active or the voltage check is not enabled
        resetBatteryVoltageCheck(widget, false)
        return
    end

    if widget.runtime.voltageCheck.completed or not widget.config.voltageCheckEnabled then
        resetBatteryVoltageCheck(widget, true)
        return
    end

    local now = os.clock()
    widget.runtime.voltageCheck.lastCheckTime = now

    if not widget.runtime.voltageCheck.batteryConnectTime then
        widget.runtime.voltageCheck.batteryConnectTime = now
        return -- not ready to check the battery voltage as we want to wait 5 seconds after connecting the battery
    end

    if (now - widget.runtime.voltageCheck.batteryConnectTime) < 5 then
        return
    end

    -- Check if voltage sensor exists, if not, get it
    if widget.config.voltageSensor and widget.config.voltageSensor:name() ~= "---" and not widget.sensors.voltage then
        widget.sensors.voltage = widget.config.voltageSensor
    end
    if not widget.sensors.voltage then
        widget.sensors.voltage = system.getSource({
            category = CATEGORY_TELEMETRY,
            name = "Voltage"
        })
        if not widget.sensors.voltage then
            widget.sensors.voltage = system.getSource({
                category = CATEGORY_TELEMETRY,
                name = "Battery Voltage"
            })
            if not widget.sensors.voltage then
                widget.sensors.voltage = system.getSource({
                    category = CATEGORY_TELEMETRY,
                    name = "VBat"
                })
                if not widget.sensors.voltage then
                    openBatteryVoltagePrompt(widget, "Voltage Sensor Not Found",
                        "Ensure there is a valid voltage sensor.")
                    resetBatteryVoltageCheck(widget, true)
                    return
                end
            end
        end
    end

    if not widget.sensors.voltage:age() then
        if debug then
            print("debug: voltage sensor age isn't valid, must search for a new sensor")
        end
        widget.sensors.voltage = nil
        return
    end

    local currentVoltage = widget.sensors.voltage:value()

    if not currentVoltage then
        if now - widget.runtime.voltageCheck.batteryConnectTime > 5 then
            openBatteryVoltagePrompt(widget, "Voltage Sensor Value Invalid", "Ensure there is a valid voltage sensor.")
            resetBatteryVoltageCheck(widget, true)
        end
        return -- not ready for voltage check, the voltage sensor value was nil
    end

    currentVoltage = currentVoltage * 100

    if not widget.sensors.cellCount and widget.config.cellCountSensor and widget.config.cellCountSensor:name() ~= "---" then
        widget.sensors.cellCount = widget.config.cellCountSensor
    end

    -- Check if cell count sensor exists (RF 2.2? only), if not, get it
    if not widget.sensors.cellCount or (widget.sensors.cellCount and not widget.sensors.cellCount:age()) then
        widget.sensors.cellCount = system.getSource({
            category = CATEGORY_TELEMETRY,
            name = "Cell Count"
        })
    end

    local cellCount
    local isCharged = false

    if widget.batteries[widget.runtime.selectedModelBattery].cellCount and
        widget.batteries[widget.runtime.selectedModelBattery].cellCount > 0 then
        cellCount = widget.batteries[widget.runtime.selectedModelBattery].cellCount
        if debug then
            print("debug: minimum voltage: " .. cellCount * widget.config.voltageCheckMinChargedCellVoltage ..
                      "; min charged voltage: " .. widget.config.voltageCheckMinChargedCellVoltage)
        end
        if debug then
            print("debug: cell count: " .. cellCount)
        end
        if debug then
            print("debug: current voltage: " .. currentVoltage)
        end
        isCharged = currentVoltage >= cellCount * widget.config.voltageCheckMinChargedCellVoltage
    elseif widget.sensors.cellCount then
        if not widget.sensors.cellCount:value() then
            if now - widget.runtime.voltageCheck.batteryConnectTime > 5 then
                openBatteryVoltagePrompt(widget, "Cell Count Sensor Value Invalid",
                    "Ensure there is a valid cell count sensor.")
                resetBatteryVoltageCheck(widget, true)
            end
            return
        end
        cellCount = math.floor(widget.sensors.cellCount:value())
        isCharged = currentVoltage >= cellCount * widget.config.voltageCheckMinChargedCellVoltage
    else
        -- Estimate cell count based on voltage
        cellCount = math.floor(currentVoltage / (widget.config.voltageCheckMinChargedCellVoltage / 100) + 0.5)
        -- To prevent accidentally reading a very low battery as a lower cell count than actual, add 1 to cellCount if the voltage is higher than cellCount * 4.35 (HV battery max cell voltage)
        if currentVoltage >= cellCount * 4.35 then
            cellCount = cellCount + 1
        end

        if cellCount == 0 then
            cellCount = 1
        end

        isCharged = currentVoltage >= cellCount * widget.config.voltageCheckMinChargedCellVoltage
    end

    if not isCharged then
        widget.runtime.voltageCheck.promptOpen = true
        local buttons = {{
            label = "Acknowledge",
            action = function()
                widget.runtime.voltageCheck.promptOpen = false
                return true
            end
        }}
        system.playFile("sound/batt_not_charged.wav")
        if widget.config.voltageCheckHapticEnabled then
            system.playHaptic(HapticPatterns[widget.config.voltageCheckHapticPattern][1])
        end
        form.openDialog({
            title = "Low Battery Voltage!",
            message = cellCount .. "S - " .. currentVoltage / 100 .. "V < Min " .. cellCount *
                widget.config.voltageCheckMinChargedCellVoltage / 100 .. "V",
            width = 350,
            buttons = buttons,
            options = TEXT_LEFT
        })
    end
    resetBatteryVoltageCheck(widget, true)
end

local function updateRemainingPercentSensor(widget, newPercent)
    if not widget.sensors.remaining or (widget.sensors.remaining and not widget.sensors.remaining:age()) then
        if debug then
            print("debug: remaining sensor is nil or invalid, searching for or creating new sensor")
        end
        widget.sensors.remaining = system.getSource({
            category = CATEGORY_TELEMETRY,
            appId = 0x4402,
            physId = 0x11,
            name = "Battery %"
        })
        if not widget.sensors.remaining then
            widget.sensors.remaining = model.createSensor()
            widget.sensors.remaining:name("Battery %")
            widget.sensors.remaining:unit(UNIT_PERCENT)
            widget.sensors.remaining:decimals(0)
            widget.sensors.remaining:appId(0x4402)
            widget.sensors.remaining:physId(0x11)
        end
    end

    if newPercent then
        widget.sensors.remaining:value(newPercent)
    end
end

local function resetRemainingPercentSensor(widget)
    if widget.sensors.remaining then
        widget.sensors.remaining:reset()
    end
end

local function resetWidget(widget)
    widget.runtime.lastReconcileTime = os.clock()
    widget.runtime.selectedModelBattery = nil
    resetRemainingPercentSensor(widget)
    widget.runtime.modelId.current = nil

    widget.runtime.alerts.percentageRemaining.lastCriticalPlayTime = nil
    widget.runtime.alerts.percentageRemaining.lastPercentage = nil

    batteryNeedsSelectionAlertActive(widget, false)

    widget.runtime.voltageCheck.completed = false
    widget.runtime.voltageCheck.promptOpen = false
    widget.runtime.voltageCheck.lastCheckTime = nil
    widget.runtime.voltageCheck.batteryConnectTime = nil
    widget.runtime.batteryChoiceFieldFocusOnBuild = false

    if widget.runtime.telemetryActiveTime then
        system.playFile("sound/telemetry_lost.wav")
    end
    widget.runtime.telemetryActiveTime = nil

    requestWidgetRebuild(widget)
end

local function getCurrentConsumption(widget)

    if not widget.sensors.consumption then
        if widget.config.consumptionSensor and widget.config.consumptionSensor:name() ~= "---" then
            widget.sensors.consumption = widget.config.consumptionSensor
            widget.sensors.lastConsumptionSensorUpdateTime = 0
        else
            if debug then
                print("debug: consumption sensor is nil, searching for new sensor")
            end
            for member = 0, 50 do
                local candidate = system.getSource({
                    category = CATEGORY_TELEMETRY_SENSOR,
                    member = member
                })
                if candidate then
                    if candidate:unit() == UNIT_MILLIAMPERE_HOUR then
                        widget.sensors.consumption = candidate
                        widget.sensors.lastConsumptionSensorUpdateTime = 0
                        break -- Exit the loop once a valid mAh sensor is found
                    end
                end
            end
        end
    end

    -- Return the value or 0 if no valid sensor was found
    if widget.sensors.consumption and widget.sensors.consumption:value() then
        local consumptionSensorAge = widget.sensors.consumption:age()
        if not consumptionSensorAge then
            widget.sensors.consumption = nil
            return {
                valid = false,
                consumption = 0
            }
        end
        consumptionSensorAge = consumptionSensorAge / 1000
        local now = os.clock()
        local consumptionSensorUpdateTime = now - consumptionSensorAge

        if debug then
            print("debug: consumption sensor has a value")
            print("debug: now: " .. tostring(now) .. "; age: " .. tostring(consumptionSensorAge))
            print("debug: consumption sensor update time: " .. tostring(consumptionSensorUpdateTime))
            print("debug: last consumption update time: " .. tostring(widget.sensors.lastConsumptionSensorUpdateTime))
            print("debug: consumption: " .. tostring(widget.sensors.consumption:value()))
        end

        if widget.sensors.lastConsumptionSensorUpdateTime <= consumptionSensorUpdateTime then
            widget.sensors.lastConsumptionSensorUpdateTime = consumptionSensorUpdateTime
            return {
                valid = true,
                consumption = math.floor(widget.sensors.consumption:value())
            }
        end
    end

    return {
        valid = false,
        consumption = 0
    }
end

local function build(widget)
    if not widget.sensors.remaining then
        updateRemainingPercentSensor(widget, nil) -- create the remaining percent sensor
    end

    form.clear()
    if #widget.batteries == 0 then
        local buttons = {{
            label = "Acknowledge",
            action = function()
                widget.runtime.alerts.noBatteries.lastPlayTime = nil
                widget.runtime.alerts.noBatteries.enabled = false
                return true
            end
        }}
        if not widget.runtime.alerts.noBatteries.lastPlayTime then
            system.playFile("sound/no_batteries.wav")
            widget.runtime.alerts.noBatteries.enabled = true
            widget.runtime.alerts.noBatteries.lastPlayTime = os.clock()
        end
        local dialog = form.openDialog({
            title = "No Batteries Found!",
            message = "No batteries were found for the widget. Please add at least one battery!",
            width = 500,
            buttons = buttons,
            options = TEXT_LEFT,
            wakeup = function()
                local now = os.clock()
                if widget.runtime.alerts.noBatteries.enabled and (now - widget.runtime.alerts.noBatteries.lastPlayTime) >
                    5 then
                    system.playFile("sound/no_batteries.wav")
                    widget.runtime.alerts.noBatteries.lastPlayTime = now
                end
            end
        })
    end

    local w, h = lcd.getWindowSize()
    if widget.runtime.telemetryActive then
        if widget.runtime.modelId.current and widget.runtime.modelId.current ~= 0 then
            for i, battery in ipairs(widget.batteries) do
                if battery.modelID == widget.runtime.modelId.current then
                    widget.runtime.selectedModelBattery = i
                    system.playFile("sound/batt_auto_selected.wav")
                    break
                end
            end
        end
        local batteryChoices = {}
        for i, battery in ipairs(widget.batteries) do
            table.insert(batteryChoices, {battery.name, i})
        end
        -- Create form and add choice field for selecting battery
        local fieldWidth = w * .8
        local fieldHeight = 40
        local batteryChoiceField = form.addChoiceField(nil, {
            x = (w / 2 - fieldWidth / 2),
            y = (h / 2 - fieldHeight / 2),
            w = fieldWidth,
            h = fieldHeight
        }, batteryChoices, function()
            return widget.runtime.selectedModelBattery
        end, function(value)
            widget.runtime.selectedModelBattery = value
            batteryNeedsSelectionAlertActive(widget, false)
            widget.runtime.batteryChoiceFieldFocusOnBuild = false
        end)

        if not widget.runtime.selectedModelBattery and widget.runtime.batteryChoiceFieldFocusOnBuild then
            batteryChoiceField:focus()
            batteryNeedsSelectionAlertActive(widget, true)
        end
    else
        local msg = "Waiting for Telemetry"
        local textW, textH = lcd.getTextSize(msg)

        form.addStaticText(nil, {
            x = (w / 2 - textW / 2),
            y = (h / 2 - textH / 2),
            w = textW,
            h = textW
        }, msg)
    end
end

local function reconcileCurrentModelId(widget)
    if widget.config.pinnedModelId and widget.config.pinnedModelId ~= 0 then
        widget.runtime.modelId.current = widget.config.pinnedModelId
    else
        if not widget.sensors.modelId and widget.config.modelIdSensor and widget.config.modelIdSensor:name() ~= "---" then
            widget.sensors.modelId = widget.config.modelIdSensor
        end
        -- Check for modelID sensor presence and its value
        if not widget.sensors.modelId or (widget.sensors.modelId and not widget.sensors.modelId:age()) then
            widget.sensors.modelId = system.getSource({
                category = CATEGORY_TELEMETRY,
                name = "Model ID"
            })
        end

        if widget.sensors.modelId and widget.sensors.modelId:value() then
            widget.runtime.modelId.current = math.floor(widget.sensors.modelId:value())
        end
    end
    -- Check if the modelID has changed since last wakeup, and if so, set the rebuildMatching flag to true
    if widget.runtime.modelId.current ~= widget.runtime.modelId.last then
        widget.runtime.modelId.last = widget.runtime.modelId.current
        requestWidgetRebuild(widget)
    end
end

local function reconcileConsumption(widget)
    if not widget.runtime.selectedModelBattery then
        return
    end
    local currentConsumption = getCurrentConsumption(widget)
    if not currentConsumption.valid then
        if debug then
            print("debug: consumption sensor isn't valid")
        end
        return
    end

    if debug then
        print("debug: current consumption is: " .. currentConsumption.consumption)
    end
    local usableCapacityPercentage = widget.config.useCapacity
    if not usableCapacityPercentage then
        usableCapacityPercentage = 100
    end

    if currentConsumption.valid then
        local usableCapacity = widget.batteries[widget.runtime.selectedModelBattery].capacity *
                                   (usableCapacityPercentage / 100)
        if debug then
            print("debug: usable mAh: " .. usableCapacity)
        end
        local remainingPercentage = 100 - (currentConsumption.consumption / usableCapacity) * 100
        if debug then
            print("debug: calculated remaining remainingPercentage: " .. remainingPercentage)
        end
        if remainingPercentage < 0 then
            remainingPercentage = 0
        end
        if debug then
            print("debug: adjusted remaining remainingPercentage: " .. remainingPercentage)
        end
        updateRemainingPercentSensor(widget, remainingPercentage) -- Update the remaining sensor

        if widget.config.remainingCalloutSwitch and widget.config.remainingCalloutSwitch:state() then
            if debug then
                print("debug: remaining callout switch is enabled")
            end
            if debug then
                print("debug: last played percentage: " ..
                          tostring(widget.runtime.alerts.percentageRemaining.lastPercentage))
            end
            local roundedPercent = math.floor(remainingPercentage + 0.5)
            if debug then
                print("debug: rounded percentage: " .. tostring(roundedPercent))
            end
            -- Calculate the trigger threshold for the given callout interval
            local remainingCalloutInterval = widget.config.remainingCalloutInterval or 10
            local triggerThreshold = 100 -
                                         (math.floor((100 - roundedPercent) / remainingCalloutInterval) *
                                             remainingCalloutInterval)
            if debug then
                print("debug: trigger threshold: " .. tostring(triggerThreshold))
            end

            if (widget.runtime.alerts.percentageRemaining.lastPercentage and roundedPercent >
                widget.runtime.alerts.percentageRemaining.lastPercentage) then
                -- weird edge case, if the consumption sensor gets reset for some reason
                widget.runtime.alerts.percentageRemaining.lastPercentage = nil
            end

            if not widget.runtime.alerts.percentageRemaining.lastPercentage or
                ((triggerThreshold - roundedPercent >= 0) and
                    (triggerThreshold - roundedPercent <= (remainingCalloutInterval / 3))) then
                local playRequired = not widget.runtime.alerts.percentageRemaining.lastPercentage or
                                         (widget.runtime.alerts.percentageRemaining.lastPercentage and
                                             widget.runtime.alerts.percentageRemaining.lastPercentage > triggerThreshold)
                if roundedPercent == 0 then
                    local now = os.clock()
                    local remainingCalloutZeroPercentInterval = widget.config.remainingCalloutZeroPercentInterval or 5
                    local lastCriticalPlayTime = widget.runtime.alerts.percentageRemaining.lastCriticalPlayTime
                    if not lastCriticalPlayTime or now - lastCriticalPlayTime > remainingCalloutZeroPercentInterval then
                        widget.runtime.alerts.percentageRemaining.lastCriticalPlayTime = now
                        playRequired = true
                    end
                end

                if playRequired then
                    widget.runtime.alerts.percentageRemaining.lastPercentage = roundedPercent
                    system.playFile("sound/battery.wav")
                    local percentageFile = "sound/numbers/" .. roundedPercent .. ".wav"
                    system.playFile(percentageFile)
                    system.playFile("sound/percent.wav")

                    if roundedPercent == 0 and widget.config.remainingCalloutHapticEnabled and
                        widget.config.remainingCalloutHapticPattern then
                        system.playHaptic(HapticPatterns[widget.config.remainingCalloutHapticPattern][1])
                    end
                end
            end
        else
            widget.runtime.alerts.percentageRemaining.lastPercentage = nil
        end

    end

end

local function wakeup(widget)
    local now = os.clock()

    batteryNeedsSelectionAlertRun(widget, now)

    local timeSinceLastReconcile = now - widget.runtime.lastReconcileTime

    if timeSinceLastReconcile >= 1 then
        widget.runtime.telemetryActive = system.getSource({
            category = CATEGORY_SYSTEM_EVENT,
            member = TELEMETRY_ACTIVE,
            options = nil
        }):state()

        if widget.runtime.telemetryActive then
            if not widget.runtime.telemetryActiveTime then
                if debug then
                    print("debug: first time telemetry active")
                end
                local currentConsumption = getCurrentConsumption(widget)
                if not currentConsumption.valid then
                    if debug then
                        print("debug: sensor is not valid yet!")
                    end
                    return
                end
                widget.runtime.telemetryActiveTime = now
                widget.runtime.batteryChoiceFieldFocusOnBuild = true

                requestWidgetRebuild(widget)
                system.playFile("sound/telemetry_active.wav")
            end
            if widget.runtime.selectedModelBattery then
                if debug then
                    print("debug: battery has been selected")
                end
                doBatteryVoltageCheck(widget)
                if debug then
                    print("debug: battery check completed")
                    print("debug: voltage check enabled: " .. tostring(widget.config.voltageCheckEnabled))
                    print("debug: voltage check prompt open: " .. tostring(widget.runtime.voltageCheck.promptOpen))
                    print("debug: voltage check completed: " .. tostring(widget.runtime.voltageCheck.completed))
                end
                if widget.config.voltageCheckEnabled and not widget.runtime.voltageCheck.promptOpen and
                    widget.runtime.voltageCheck.completed or not widget.config.voltageCheckEnabled then
                    if debug then
                        print("debug: reconciling consumption")
                    end
                    reconcileConsumption(widget)
                end
            end
            reconcileCurrentModelId(widget)
            widget.runtime.lastReconcileTime = now
        elseif not widget.runtime.telemetryActive and timeSinceLastReconcile >= 5 then
            resetWidget(widget)
        end
    end

    if widget.runtime.widgetRebuildRequired then
        build(widget)
        widget.runtime.widgetRebuildRequired = false
    end
end

-- This function is called when the user first selects the widget from the widget list, or when they select "configure widget"
local function configure(widget)
    form.clear()
    widget.panels.batteries = form.addExpansionPanel("Batteries")
    fillBatteryPanel(widget)

    widget.panels.settings = form.addExpansionPanel("Settings")
    widget.panels.sensors = form.addExpansionPanel("Telemetry Sensors")
    fillSettingsPanel(widget)
end

local function paint(widget)
end

local function init()
    system.registerWidget({
        key = "battmgr",
        name = "Battery Manager",
        create = create,
        build = build,
        wakeup = wakeup,
        paint = paint,
        configure = configure,
        read = read,
        write = write
    })
end

return {
    init = init
}
