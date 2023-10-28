-- Registers a custom packet ID to send and receive data packets via the command interface.
-- (page 54 of scripting ref manual v4)
cmd.register(0xB0); -- Measure only
cmd.register(0xB1); -- Position control
cmd.register(0xB2); -- Speed control

def_speed = 5;
is_speed = false;

-- Get number of FMF fingers
nfin = 0;

for i = 0, 1 do
    -- Finger numbering starts at 0. There are available 3 types:
    -- "generic", "fmf" - Force Measurment Finger, "dsa" - Tactile Sensing Finger
    -- (page 60 of scripting ref manual v4)
    if finger.type(i) == "fmf" then
        nfin = nfin + 1;
    else
        break;
    end
end

printf("#FMF fingers: %d\n", nfin)

function process()
    -- Receives data packets (as table).
    -- Blocks until a data packet was received
    -- (page 58 of scripting ref manual v4)
    id, payload = cmd.read();

    --------------------
    --- Measurements ---
    --------------------

    -- Returns true if the fingers are currently moving or
    -- false if the previously given movement command is already completed
    -- (page 45 of scripting ref manual v4)
    busy = mc.busy()

    -- Returns the current blocking state of the fingers
    -- (page 38 of scripting ref manual v4)
    blocked = mc.blocked()

    -- Returns the current distance between the fingers in mm
    -- (page 37 of scripting ref manual v4)
    pos = mc.position();
    
    if id == 0xB1 then
        
        ------------------------
        --- Position control ---
        ------------------------

        -- Table of 4 bytes (little-endian) to Lua number conversion (page 13 of scripting ref manual v4)
        cmd_width = bton({payload[2], payload[3], payload[4], payload[5]});
        cmd_speed = bton({payload[6], payload[7], payload[8], payload[9]});

        printf("Got command %f, %f\n", cmd_width, cmd_speed);
        
        if busy then
            -- Abort the current movement immediately and disable the position controller
            -- (page 44 of scripting ref manual v4)
            mc.stop();
        end

        -- Initiate an advanced pre-positioning movement of the fingers.
        -- Accepts certain flags to control the motion.
        -- Returns an error code as a result of the movement.
        -- Uses an acceleration- and jerk-limited speed profile for motion (sin^2(x) profile)
        -- (page 45-46 of scripting ref manual v4)
        mc.move(cmd_width, math.abs(cmd_speed), 0)
        
    elseif id == 0xB2 then
    
        -----------------------
        --- Velocity control --
        -----------------------

        -- Table of 4 bytes (little-endian) to Lua number conversion (page 13 of scripting ref manual v4)
        cmd_speed = bton({payload[6],payload[7],payload[8],payload[9]});

        print("set_speed");
        print(cmd_speed);

        is_speed = true;
        def_speed = cmd_speed;

        -- set the speed between the fingers (relative speed) in mm/s
        -- (page 36 of scripting ref manual v4)
        mc.speed(cmd_speed);
        
    end        
       
    ---------------
    --- Actions ---
    ---------------
    
    -- Stop if in speed mode and the fingers are heading out of valid range
    if blocked and is_speed and pos <= 0 and def_speed < 0 then
        print("stop");
        
        -- Abort the current movement immediately and disable the position controller
        -- (page 44 of scripting ref manual v4)
        mc.stop();

        is_speed = false;
    end

    if blocked and is_speed and pos >= 110 and def_speed > 0 then
        print("stop");
        
        -- Abort the current movement immediately and disable the position controller
        -- (page 44 of scripting ref manual v4)
        mc.stop();
        
        is_speed = false;
    end           

    --------------------
    --- Measurements ---
    --------------------

    -- returns current system state flags as 32-bit wide integer value
    -- (page 18 of scripting ref manual v4)
    -- All system state flags are listed on page 87 of scripting ref manual v4
    state = gripper.state();

    -- returns true if the fingers are currently moving
    -- (page 45 of scripting ref manual v4)
    busy = mc.busy();
    
    -- returns true if the fingers are blocked
    -- (page 38 of scripting ref manual v4)
    blocked = mc.blocked();

    -- returns the current distance between the fingers in mm
    -- (page 37 of scripting ref manual v4)
    pos = mc.position();

    -- returns the current speed between the fingers (relative speed) in mm/s
    -- (page 36 of scripting ref manual v4)
    speed = mc.speed();

    -- returns the approximated gripping force computed from the motor current in Newton
    -- (useful with force measurement fingers installed otherwise it is the same as mc.force())
    -- (page 39 of scripting ref manual v4)
    force = mc.aforce();

    force_l = 0;
    force_r = 0;
    
    if finger.type(0) == "fmf" then
        -- Reads the current data from a predefined finger.
        -- The data format depends on the finger type.
        -- (page 62 of scripting ref manual v4)
        force_l = finger.data(0)
    else
        force_l = force
    end
    
    if finger.type(1) == "fmf" then
        -- Reads the current data from a predefined finger.
        -- The data format depends on the finger type.
        -- (page 62 of scripting ref manual v4)
        force_r = finger.data(1)
    end
    
    -- print("Force on left finger: " .. force_l);
    -- print("Force on right finger: " .. force_r);

    -- If a host is connected via the specified command interface then true
    -- (page 54 of scripting ref manual v4)
    if cmd.online() then

        -- Sends a data packet using a registered ID.
        -- (page 55-56 of scripting ref manual v4)

        -- The payload of the data packet is passed as a variable argument list that can contain
        -- integer types, boolean types and string types and well as tables containing these types.
        -- The maximum length for a custom command is 65536 bytes.
        
        -- The following conversion rules will be applied:
        -- - Integer and Number types are treated as single bytes, i.e. have a valid range of 0 to 255.
        --   If this range is exceeded, the function raises a runtime error. To send a number value, use the ntob()
        -- - Boolean values are converted into a single byte set to 0 and 1, respectively.
        -- - String values are converted into a sequence of bytes (without a trailing zero).
        -- - Tables can contain the above types and can be nested at a total of up to 5 levels.
        cmd.send(
            id,
            -- Converts the given error code into its two-byte representation
            -- (page 15 of scripting ref manual v4)
            etob(E_SUCCESS),
            -- Only the lowest byte of state is sent!
            state % 256,
            -- Lua number to table of 4 bytes (little-endian) conversion
            -- (page 14 of scripting ref manual v4)
            { ntob(pos), ntob(speed), ntob(force), ntob(force_l), ntob(force_r) }
        );

    end
end

while true do
    -- If a host is connected via the specified command interface then true
    -- (page 54 of scripting ref manual v4)
    if cmd.online() then
        -- (https://www.lua.org/manual/5.3/manual.html#pdf-pcall)
        -- Calls function `process` in protected mode. It means that `pcall`
        -- catches any error inside `process` and returns a status code.
        -- Its first result is the status code (a boolean), which is true if
        -- the call succeeds without errors. In such case, pcall also returns
        -- all results from the call, after this first result.
        -- 
        -- status, results = pcall(process)
        -- 
        -- In case of any error, pcall returns false plus the error message.
        -- 
        -- status, error = pcall(process)
        --
        if not pcall(process) then
            print("Error occured");
            sleep(100); -- in milliseconds (page 13 of scripting ref manual v4)
        end
    else
        sleep(100) -- in milliseconds (page 13 of scripting ref manual v4)
    end
end