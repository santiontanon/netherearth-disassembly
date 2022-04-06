; --------------------------------
;
; "Nether Earth" by Argus Press Software, 1986
; Disassembled by Santiago Ontañón in 2022
; 
; --------------------------------
;
; Notes:
;
; - All the symbol names and comments in this file are my own interpretation of the original source 
;   code, they could be wrong. So, take them all with a grain of salt! And if you see any errors, 
;   please report!
;
; - Game binary disassembled using MDL: https://github.com/santiontanon/mdlz80optimizer
;
; - I decided to prefix each label by their address, e.g. "La600_start" instead of just "start" as, 
;   often, the code makes assumptions about these addresses. For example, when it checks if the 
;   most-significant byte of a pointer if #dc or #fd to know we are out of bounds of a map. By 
;   making the map label "Ldd00_map", it is at least clear that checking for "#dc" is to see if the 
;   pointer is lower than #dd00, which is the beginning of the map.
;
; - There is some unreachable code (see label Lae29) in the code base, that contains code that is 
;   probably left-over code.
; 
; - There are also two gaps in the zone of RAM designated for variables. So, probably some 
;   variables were defined, but unused in the final version of the code (search for "unused bytes" 
;   in this file).
; 
; - The music system is very interesting for a 48K Spectrum model:
;     - Look at "Lc4a7_title_music_loop"
;     - Basically, when playing music, the game runs a constant loop that iterates over 3 
;       oscillators that produce sound.
;     - These oscillators are just 3 loops in the code that make the speaker vibrate with some 
;       fixed frequencies.
;     - The interrupt routine has a script that, using self-modifiable code, modifies the
;       oscillator parameters in the loop.
;     - So, basically, the loop acts as a sound chip, and the interrupt basically sets its 
;       parameters, mimicking 3 channel sound.
;     - Since it's a dedicated loop, nothing can run in parallel with it. So, as soon as the player 
;       presses any key, music stops.
;
; - SFX:
;     - The game reads from the addresses in the Spectrum ROM and uses them to produce sound. This 
;       is probably just some random sound (as those values are not a wave, but assembler code), 
;       but the programmers chose different parts of the ROM that produce slightly different 
;       sounds when reproduced, which is pretty smart.
;
; - Game-play details, not fully documented in the instructions:
;     - Weapons all fly at the same altitude (10) regardless of the height of the robot.
;     - Electronics:
;         - increase the range of weapons by 1 tile (what the manual states being 3 miles).
;         - they also increase the distance robots can "see" an opponent from 10 to 12 tiles.
;     - Each player can have at most 24 robots.
;     - There can only be 5 bullets at a time in the whole game:
;         - one bullet for the player controlled robot
;         - two bullets fired by friendly robots
;         - two bullets fired by enemy robots
;     - How much damage weapons deal is quite curious:
;         - The game calculates (60 - (robot height + ground height))/4 as the "base damage".
;         - Then cannon deals 2x the base damage, missiles 3x, and phasers 4x. (the Spanish 
;           instruction manual is wrong here, stating that missiles do the same damage as cannon, 
;           English is correct).
;         - So, robots that are on high ground receive less damage! Stand on a mountain to make a 
;           robot more resistant!
;     - Since a robot can have at most 3 weapons, we have (see the 
;       Ld7b4_piece_heights data below):
;         - The maximum height of a robot is: 11 + 6 + 7 + 7 + 7 = 38 (bipod, missiles, phase, 
;           nuclear, electronics). This is the most resistant robot!
;         - The minimum height of a robot is: 7 + 6 = 13 (tracks, cannon). This is the weakest 
;           robot!
;     - So, for example: phasers against the weakest robot (at ground level) deal: ((60 - 13)/4)*4 
;       = 44 damage.
;     - The robot/enemy AI is extremely simple:
;         - see "Lb154_robot_ai_update" for the code that implements the AI of the robots, 
;           including their limited "path-finding", and targetting.
;         - see "Lb7f4_update_enemy_ai" for the code that implements the strategy of the enemy 
;           player.
; 
; - Terminology:
;     - I often use the abbreviation "ptr." for "pointer".
;     - I often use the term "one-hot" (vector/byte). This is a way to represent numbers, where 
;       only one bit of the byte is set to 1, and the others are zero. The number encoded is the
;       index of the bit that is set to 1. For example:
;         - 1 encoded as a one-hot vector is: 00000001
;         - 2 encoded as a one-hot vector is: 00000010
;         - 3 encoded as a one-hot vector is: 00000100
;         - 4 encoded as a one-hot vector is: 00001000
;         - etc.
;
; --------------------------------


; --------------------------------
; BIOS Functions and constants:
; - Information obtained from:
;   https://worldofspectrum.net/pub/sinclair/books/s/SpectrumMachineCodeReferenceGuideThe.pdf
L0205_BIOS_KEYCODE_TABLE: equ #0205
L028e_BIOS_POLL_KEYBOARD: equ #028e  ; Polls keyboard and builds up key code in DE
L0556_BIOS_READ_FROM_TAPE: equ #0556  ; Load if carry set, load tape header if A=0 (nz=data). 
                                      ; IX=address, DE=byte count
L0562_BIOS_READ_FROM_TAPE_SKIP_TESTS: equ #0562
L04c2_BIOS_CASSETTE_SAVE: equ #04c2
L04d0_BIOS_CASSETTE_SAVE_SKIP_TESTS: equ #04d0

L4000_VIDEOMEM_PATTERNS: equ #4000
L5800_VIDEOMEM_ATTRIBUTES: equ #5800

ULA_PORT: equ #fe
KEMPSTON_JOYSTICK_PORT: equ 31
INTERFACE2_JOYSTICK_PORT_MSB: equ #ef

COLOR_BRIGHT: equ #40
COLOR_BLACK: equ 0
COLOR_BLUE: equ 1
COLOR_RED: equ 2
COLOR_PINK: equ 3
COLOR_GREEN: equ 4
COLOR_CYAN: equ 5
COLOR_YELLOW: equ 6
COLOR_WHITE: equ 7
PAPER_COLOR_MULTIPLIER: equ 8


; --------------------------------
; Commands recognized by Ld42d_execute_ui_script:
CMD_END: equ 0
CMD_SET_POSITION: equ 1
CMD_SET_ATTRIBUTE: equ 2
CMD_NEXT_LINE: equ 3
CMD_SET_SCALE: equ 4


; --------------------------------
INPUT_KEYBOARD: equ 1
INPUT_KEMPSTON: equ 2
INPUT_INTERFACE2: equ 3


; --------------------------------
; Game constants:
INITIAL_PLAYER_RESOURCES: equ 20
MAX_ROBOTS_PER_PLAYER: equ 24
MAX_BULLETS: equ 5
N_WARBASES: equ 4
N_FACTORIES: equ 24
BUILDING_CAPTURE_TIME: equ 144
MIN_INTERRUPTS_PER_GAME_CYCLE: equ 10  ; game maximum speed is 5 frames per second.

MAX_PLAYER_ALTITUDE: equ 48
MIN_PLAYER_X: equ 14
MAX_PLAYER_X: equ 501

MAP_LENGTH: equ 512  ; x coordinate
MAP_WIDTH: equ 16  ; y coordinate

ROBOT_ORDERS_STOP_AND_DEFEND: equ 0
ROBOT_ORDERS_ADVANCE: equ 1
ROBOT_ORDERS_RETREAT: equ 2
ROBOT_ORDERS_DESTROY_ENEMY_ROBOTS: equ 3
ROBOT_ORDERS_DESTROY_ENEMY_FACTORIES: equ 4
ROBOT_ORDERS_DESTROY_ENEMY_WARBASES: equ 5
ROBOT_ORDERS_CAPTURE_NEUTRAL_FACTORIES: equ 6
ROBOT_ORDERS_CAPTURE_ENEMY_FACTORIES: equ 7
ROBOT_ORDERS_CAPTURE_ENEMY_WARBASES: equ 8

ROBOT_CONTROL_AUTO: equ 0
ROBOT_CONTROL_PLAYER_LANDED: equ 1
ROBOT_CONTROL_DIRECT_CONTROL: equ 2
ROBOT_CONTROL_ENEMY_AI: equ 128

WEAPON_RANGE_DEFAULT: equ 5
WEAPON_RANGE_MISSILES: equ 7


; --------------------------------
; Game structs:
ROBOT_STRUCT_SIZE: equ 16
ROBOT_STRUCT_MAP_PTR: equ 0  ; 2 bytes (the first byte set to 0 when there is no robot in this 
                             ; struct).
ROBOT_STRUCT_X: equ 2  ; 2 bytes
ROBOT_STRUCT_Y: equ 4
ROBOT_STRUCT_DESIRED_MOVE_DIRECTION: equ 5
ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING: equ 6
ROBOT_STRUCT_PIECES: equ 7
ROBOT_STRUCT_DIRECTION: equ 8  ; one-hot representation: #01, #02, #04, #08
ROBOT_STRUCT_HEIGHT: equ 9
ROBOT_STRUCT_CONTROL: equ 10
ROBOT_STRUCT_ORDERS: equ 11
ROBOT_STRUCT_STRENGTH: equ 12
ROBOT_STRUCT_ALTITUDE: equ 13
ROBOT_STRUCT_ORDERS_ARGUMENT: equ 14  ; This can be # of miles, target robot index, etc.
ROBOT_STRICT_CYCLES_TO_NEXT_UPDATE: equ 15


BULLET_STRUCT_SIZE: equ 9
BULLET_STRUCT_MAP_PTR: equ 0  ; 2 bytes (the first byte set to 0 when there is no bullet in this 
                              ; struct).
BULLET_STRUCT_X: equ 2  ; 2 bytes
BULLET_STRUCT_Y: equ 4
BULLET_STRUCT_DIRECTION: equ 5
BULLET_STRUCT_RANGE: equ 6
BULLET_STRUCT_TYPE: equ 7  ; 1: cannon, 2: missiles, 3: phasers
BULLET_STRUCT_ALTITUDE: equ 8


BUILDING_STRUCT_SIZE: equ 5
BUILDING_STRUCT_X: equ 0  ; 2 bytes
BUILDING_STRUCT_Y: equ 2
BUILDING_STRUCT_TYPE: equ 3  ; contains type + owner (owner in the most-significant bits: bit 6 
                             ; player 1, bit 5 player 2). bit 7 indicates building is destroyed.
BUILDING_STRUCT_TIMER: equ 4  ; this counts the time the building is occupied by a robot


BUILDING_DECORATION_STRUCT_SIZE: equ 3
BUILDING_DECORATION_STRUCT_MAP_PTR: equ 0
BUILDING_DECORATION_STRUCT_TYPE: equ 2


; --------------------------------
; RAM variables/buffers in the low region of RAM:
; The first 3200 bytes (starting at #5b00) are used as a double buffer, to render
; the screen there, before it is copied over to the video memory. 3200 bytes, as
; the game area is 160x160 pixels wide. So, 160/8 = 20 bytes per line, and 20*160 = 3200.
L5b00: equ #5b00
L5b00_double_buffer: equ #5b00


; --------------------------------
; Game graphic data"
    org #6780

    include "netherearth-annotated-data.asm"
    ds #a600 - $, 0  ; 150 bytes of empty space until the game code starts.


; --------------------------------
; Game entry point    
La600_start:
    ; Set up the interrupts:
    di
        ld sp, 0
        ld hl, Lfe00_interrupt_vector_table
        ld bc, #00fd
        ; Write #fd to the interrupt vector table 257 times
La60a_interrupt_vector_table_init_loop:
        ld (hl), c
        inc hl
        djnz La60a_interrupt_vector_table_init_loop
        ld (hl), c
        ld a, #c3  ; jp opcode
        ld (Lfdfd_interrupt_jp), a
        ld hl, Ld59c_empty_interrupt
        ld (Lfdfe_interrupt_pointer), hl  ; sets the interrupt routine
        ld a, #fe
        ld i, a  ; sets the interrupt vector tp #fe00
        im 2
    ei

    ; Initialize the random number generator:
    ld hl, 12345  ; random seed
    ld (Lfd00_random_seed), hl
    ld (Lfd00_random_seed+2), hl
    call Lc100_title_screen
    jr nz, La68e_game_loop_start ; Start from a saved game

    ; Start new game from scratch:
    ; Clear memory buffers:
    ld hl, Lda00_player1_robots
    ld de, Lda00_player1_robots+1
    ld bc, 2*MAX_ROBOTS_PER_PLAYER*ROBOT_STRUCT_SIZE - 1
    ld (hl), 0
    ldir
    ld hl, Lfd04_script_video_pattern_ptr
    ld de, Lfd04_script_video_pattern_ptr+1
    ld bc, 248
    ld (hl), 0
    ldir  ; This clears a whole set of in-game variables starting at Lfd04_script_video_pattern_ptr
    ld hl, Lff01_building_decorations
    ld de, Lff01_building_decorations + 1
    ld bc, 200  ; Potential optimization: change to 167 since only 168 bytes need to be cleared 
                ; here.
    ld (hl), 0
    ldir
    ld hl, Ld7d3_bullets
    ld de, Ld7d3_bullets+1
    ld bc, MAX_BULLETS * BULLET_STRUCT_SIZE - 1
    ld (hl), 0
    ldir

    ; Initialize variables:
    ld hl, Ldd00_map
    ld (Lfd06_scroll_ptr), hl
    ld hl, 0
    ld (Lfd0a_scroll_x), hl
    ld hl, 17
    ld (Lfd0e_player_x), hl  ; set player start x
    ld a, 10
    ld (Lfd0d_player_y), a  ; set player start y
    xor a
    ld (Lfd10_player_altitude), a  ; set player start altitude
    ld a, 3
    ld (Lfd30_player_elevate_timer), a  ; make the player float a bit right at game start
    ld a, INITIAL_PLAYER_RESOURCES
    ld (Lfd22_player1_resource_counts), a
    ld (Lfd4a_player2_resource_counts), a
    call Lbc6f_initialize_map


; --------------------------------
; This is the main game loop:
La68e_game_loop_start:
    call Lcfd7_draw_blank_map_in_buffer
    call Ld0ca_draw_in_game_screen_and_hud
    ld hl, Ld566_interrupt
    ld (Lfdfe_interrupt_pointer), hl
La69a_game_loop:
    call Ld37c_read_keyboard_joystick_input
    call Laf11_player_ship_keyboard_control
    call Lb0ca_update_robots_bullets_and_ai
    call Lccbd_redraw_game_area
    call Lad62_increase_time
    call Lcca0_compute_player_map_ptr
    bit 6, (hl)
    jr z, La70d_game_loop_continue
    call Lcdd8_get_robot_at_ptr
    jr nz, La6c8_not_landed_on_a_robot
    ld a, b
    cp MAX_ROBOTS_PER_PLAYER + 1  ; if it's not one of the player's robots, ignore
    jr c, La70d_game_loop_continue
    ld a, (Lfd10_player_altitude)
    sub (iy + ROBOT_STRUCT_HEIGHT)
    sub (iy + ROBOT_STRUCT_ALTITUDE)
    call z, La720_land_on_robot  ; if we are right on top of the robot, control it!
    jr La70d_game_loop_continue

La6c8_not_landed_on_a_robot:
    call Lcdf5_find_building_decoration_with_ptr
    jr nz, La70d_game_loop_continue  ; player is not on top of any ownable building
    ld a, (iy + BUILDING_DECORATION_STRUCT_TYPE)
    or a
    jr nz, La70d_game_loop_continue  ; player is not on top of an "H" decoration
    ld a, (Lfd10_player_altitude)
    cp 15
    jr nz, La70d_game_loop_continue  ; player is not at the right height
    ld l, (iy + BUILDING_DECORATION_STRUCT_MAP_PTR)
    ld a, (iy + BUILDING_DECORATION_STRUCT_MAP_PTR + 1)
    add a, 8  
    ld h, a
    ; check for bit 6 in a 2x2 rectangle around the building map ptr, this is to
    ; make sure the building is still there and not destroyed:
    ld a, (hl)
    inc h
    inc h
    or (hl)
    dec hl
    or (hl)
    inc hl
    inc hl
    or (hl)
    and #40
    jr nz, La70d_game_loop_continue  ; not landed on a warbase
    call Lc849_robot_construction_if_possible
    ; Reset state of newly created robot:
    ld (iy + ROBOT_STRUCT_DESIRED_MOVE_DIRECTION), 4  ; more down by default
    ld (iy + ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING), 5  ; walk 5 steps after exiting the 
                                                               ; base, and stop
    ld (iy + ROBOT_STRUCT_ORDERS), ROBOT_ORDERS_STOP_AND_DEFEND
    ld (iy + ROBOT_STRUCT_STRENGTH), 100
    ld (iy + ROBOT_STRICT_CYCLES_TO_NEXT_UPDATE), 1
    call Lbb40_count_robots
    call Ld293_update_stats_in_right_hud
La70d_game_loop_continue:
    ld a, (Lfd0c_keyboard_state)
    bit 6, a  ; restart key
    jp nz, La600_start
    bit 5, a  ; save game key
    jp z, La69a_game_loop
    call Lc28d_save_game
    jp La68e_game_loop_start


; --------------------------------
; Player lands on a robot.
; Input:
; - iy: robot player landed on
La720_land_on_robot:
    push iy
    pop ix
    ld (ix + ROBOT_STRUCT_CONTROL), ROBOT_CONTROL_PLAYER_LANDED
    ld a, 4
    ld (Lfd1f_cursor_position), a
    ld a, 1
    ld (Lfd39_current_in_game_right_hud), a
La732_land_on_robot_internal:
    call Ld2f6_clear_in_game_right_hud
    call Ld42d_execute_ui_script
    ; script start:
        db CMD_SET_POSITION, #04, #17
        db CMD_SET_ATTRIBUTE, #4d
        db "DIRECT  "
        db CMD_NEXT_LINE
        db " CONTROL"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "GIVE    "
        db CMD_NEXT_LINE
        db "  ORDERS"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "COMBAT  "
        db CMD_NEXT_LINE
        db "    MODE"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "LEAVE   "
        db CMD_NEXT_LINE
        db "   ROBOT"
        db CMD_SET_POSITION, #11, #17
        db CMD_SET_ATTRIBUTE, #46
        db "-ORDERS-"
        db CMD_END
    ; script end:
    ; Print the robot current orders in the hud:
    ld b, (ix + ROBOT_STRUCT_ORDERS)
    inc b
    ld hl, La848_possible_robot_order_names - 27
    ld de, 27
La79f_get_orders_name_loop:
    add hl, de
    djnz La79f_get_orders_name_loop
    ; Copy the current orders to the script below, so we can draw it:
    ld de, La7b2_current_orders_buffer
    ld bc, 27
    ldir
    call Ld42d_execute_ui_script
    ; script start:
        db CMD_SET_POSITION, #12, #17
        db CMD_SET_ATTRIBUTE, #45
La7b2_current_orders_buffer:
        db #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
        db #00, #00, #00, #00, #00, #00, #00, #00, #00, #00, #00
    ; script end:
    ld a, (ix + ROBOT_STRUCT_ORDERS)
    dec a
    cp 2
    jr nc, La7e4_no_miles
    ; If there orders are advance/retreat, display the # of miles:
    call Ld42d_execute_ui_script
    ; script start:
        db CMD_SET_POSITION, #13, #19
        db CMD_END
    ; script end:
    ld a, (ix + ROBOT_STRUCT_ORDERS_ARGUMENT)
    srl a
    call Ld3e5_render_8bit_number
La7e4_no_miles:
    call La81d_draw_robot_strength
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #0037
    ld e, 5
    ld a, (Lfd1f_cursor_position)
    call Lacd7_right_hud_menu_control
    ld (Lfd1f_cursor_position), a
    dec a
    jp z, La93b_direct_control
    dec a
    jp z, La971_give_orders
    dec a
    jp z, Lac00_combat_mode
    ld a, 120
    call Lccac_beep
    xor a
    ld (ix + ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING), a
    ld (ix + ROBOT_STRUCT_CONTROL), a  ; robot controls itself again
    ld a, 5
    ld (Lfd30_player_elevate_timer), a  ; make the player float a bit after exiting a robot
La812_exit_robot:
    call Ld2f6_clear_in_game_right_hud  ; potential optimization: this line is not needed
    xor a
    ld (Lfd39_current_in_game_right_hud), a
    call Ld1e5_draw_in_game_right_hud  ; potential optimization: tail recursion
    ret


; --------------------------------
; Draws the remaining strength (hit points) of a robot.
La81d_draw_robot_strength:
    call Ld42d_execute_ui_script
    ; script start:
        db CMD_SET_POSITION, #16, #17
        db CMD_SET_ATTRIBUTE, #46
        db "STRENGTH"
        db CMD_SET_POSITION, #17, #19
        db CMD_SET_ATTRIBUTE, #47
        db CMD_END
    ; script end:
    ld a, (ix + ROBOT_STRUCT_STRENGTH)
    or a
    jp p, La83b_positive_strength
    xor a
La83b_positive_strength:
    ld l, a
    ld h, 0
    ld e, ' '
    call Ld401_render_16bit_number_3digits
    ld a, '%'
    jp Ld427_draw_character_saving_registers


; --------------------------------
La848_possible_robot_order_names:
    db "  STOP  "
    db CMD_NEXT_LINE
    db "  AND   "
    db CMD_NEXT_LINE
    db " DEFEND "
    db CMD_END

    db "ADVANCE "
    db CMD_NEXT_LINE
    db "        "
    db CMD_NEXT_LINE
    db " MILES  "
    db CMD_END

    db "RETREAT "
    db CMD_NEXT_LINE
    db "        "
    db CMD_NEXT_LINE
    db " MILES  "
    db CMD_END

    db "DESTROY "
    db CMD_NEXT_LINE
    db " ENEMY  "
    db CMD_NEXT_LINE
    db " ROBOTS "
    db CMD_END
    
    db "DESTROY "
    db CMD_NEXT_LINE
    db " ENEMY  "
    db CMD_NEXT_LINE
    db "FACTORYS"
    db CMD_END
    
    db "DESTROY "
    db CMD_NEXT_LINE
    db " ENEMY  "
    db CMD_NEXT_LINE
    db "WARBASES"
    db CMD_END
    
    db "CAPTURE "
    db CMD_NEXT_LINE
    db "NEUTRAL "
    db CMD_NEXT_LINE
    db "FACTORYS"
    db CMD_END
    
    db "CAPTURE "
    db CMD_NEXT_LINE
    db " ENEMY  "
    db CMD_NEXT_LINE
    db "FACTORYS"
    db CMD_END
    
    db "CAPTURE "
    db CMD_NEXT_LINE
    db " ENEMY  "
    db CMD_NEXT_LINE
    db "WARBASES"
    db CMD_END


; --------------------------------
; Jumps to the direct-control interface, and goes back to the "land on robot" menu after that.
La93b_direct_control:
    call La941_direct_control_internal
    jp La732_land_on_robot_internal


; --------------------------------
; Direct control of a robot.
La941_direct_control_internal:
    ld (ix + ROBOT_STRUCT_CONTROL), ROBOT_CONTROL_DIRECT_CONTROL
    ld (ix + ROBOT_STRUCT_DESIRED_MOVE_DIRECTION), 0  ; stop the automatic movement of the robot
    call Lad57_wait_until_no_keys_pressed
La94c_direct_control_loop:
    call Lb0ca_update_robots_bullets_and_ai
    call Lccbd_redraw_game_area
    call Lb048_update_radar
    call Lad62_increase_time
    call La81d_draw_robot_strength
    ld a, (ix + 1)
    or a
    ret z  ; If the robot is destroyed, exit.
    call Ld37c_read_keyboard_joystick_input
    and 16  ; If we press "fire", exit
    jr z, La94c_direct_control_loop
    ld (ix + ROBOT_STRUCT_CONTROL), ROBOT_CONTROL_PLAYER_LANDED
    ld a, 120
    call Lccac_beep
    ret


; --------------------------------
; This function implements the menu to give new orders to a robot.
La971_give_orders:
    call Ld2f6_clear_in_game_right_hud
    call Ld42d_execute_ui_script
    ; script start:
        db CMD_SET_POSITION, #04, #18
        db CMD_SET_ATTRIBUTE, #47
        db "SELECT"
        db CMD_NEXT_LINE
        db "ORDERS"
        db CMD_SET_ATTRIBUTE, #4d
        db CMD_SET_POSITION, #07, #17
        db "STOP AND"
        db CMD_NEXT_LINE
        db "  DEFEND"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "ADVANCE "
        db CMD_NEXT_LINE
        db "?? MILES"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "RETREAT "
        db CMD_NEXT_LINE
        db "?? MILES"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "SEARCH &"
        db CMD_NEXT_LINE
        db " DESTROY"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "SEARCH &"
        db CMD_NEXT_LINE
        db " CAPTURE"
        db CMD_END
    ; script end:
    call La81d_draw_robot_strength
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #0097  ; ptr to the start of the menu attributes
    ld e, 6  ; this menu has 5 options
    ld a, 1  ; we start in option 1
    call Lacd7_right_hud_menu_control
    push af
        call Lad57_wait_until_no_keys_pressed
    pop af
    dec a
    jr nz, Laa0c_no_stop_and_defend
    ld (ix + ROBOT_STRUCT_ORDERS), a  ; stop and defend
    ld a, 120
    call Lccac_beep
    jp La732_land_on_robot_internal
Laa0c_no_stop_and_defend:
    cp 3
    jp nc, Laacf_give_capture_or_destroy_orders
    ; We have selected advance or retreat:
    ld (ix + ROBOT_STRUCT_ORDERS), a
    push af
        call Ld2f6_clear_in_game_right_hud
    pop af
    dec a
    jr nz, Laa2f_retreat
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #05, #17
        db CMD_SET_ATTRIBUTE, #4f
        db "ADVANCE "
        db CMD_END
    ; Script end:
    jr Laa40_advance_or_retreat_drawn
Laa2f_retreat:
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #05, #17
        db CMD_SET_ATTRIBUTE, #4f
        db "RETREAT "
        db CMD_END
    ; Script end:
Laa40_advance_or_retreat_drawn:
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_NEXT_LINE
        db "?? MILES"
        db CMD_SET_POSITION, #09, #17
        db CMD_SET_ATTRIBUTE, #45
        db " SELECT"
        db CMD_NEXT_LINE
        db "DISTANCE"
        db CMD_SET_POSITION, #0d, #18
        db CMD_SET_ATTRIBUTE, #46
        db "0 MILES"
        db CMD_END
    ; Script end:
    ld d, 0  ; 0 miles to start
Laa70_select_miles_loop:
    push de
        call La81d_draw_robot_strength
        call Lb0ca_update_robots_bullets_and_ai
        call Lccbd_redraw_game_area
        call Lb048_update_radar
        call Lad62_increase_time
    pop de
    ld a, (ix + 1)
    or a  ; If robot is destroyed, exit.
    jp z, La812_exit_robot
    call Ld37c_read_keyboard_joystick_input
    bit 4, a
    jr nz, Laab8_miles_selected  ; If fire pressed
    ld c, d
    rrca
    rrca
    and 3
    jr z, Laa70_select_miles_loop  ; if we have not pressed up/down
    and 2
    ld b, a
    add a, a
    add a, a
    add a, b
    sub 5  ; If we have pressed up, a = 5, otherwise, a = -5
    add a, c  ; c was storing the # of miles
    cp 51
    jr nc, Laa70_select_miles_loop  ; Limit miles to 50
    ld d, a  ; update the # miles
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #0d, #17
        db CMD_SET_ATTRIBUTE, #46
        db CMD_END
    ; Script end
    ld a, d
    call Ld3e5_render_8bit_number
    ld a, 20
    call Lccac_beep
    jr Laa70_select_miles_loop

Laab8_miles_selected:
    ld a, d
    rlca  ; multiply by 2: 1 mile == 2 coordinate units
    ld (ix + ROBOT_STRUCT_ORDERS_ARGUMENT), a  ; set the number of miles to advance
    or a
    jr nz, Laac4  ; "advance/retreat 0 miles" is equivalent to stop and defend.
    ld (ix + ROBOT_STRUCT_ORDERS), ROBOT_ORDERS_STOP_AND_DEFEND
Laac4:
    ld a, 120
    call Lccac_beep
    call Lad57_wait_until_no_keys_pressed
    jp La732_land_on_robot_internal

Laacf_give_capture_or_destroy_orders:
    jp nz, Lab4e_give_capture_orders
    ; Destroy:
    call Ld2f6_clear_in_game_right_hud
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #04, #17
        db CMD_SET_ATTRIBUTE, #4f
        db "SEARCH &"
        db CMD_NEXT_LINE
        db " DESTROY"
        db CMD_SET_POSITION, #08, #18
        db CMD_SET_ATTRIBUTE, #45
        db "SELECT"
        db CMD_NEXT_LINE
        db "TARGET"
        db CMD_SET_POSITION, #0c, #17
        db CMD_SET_ATTRIBUTE, #4d
        db "ENEMY   "
        db CMD_NEXT_LINE
        db "  ROBOTS"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "ENEMY   "
        db CMD_NEXT_LINE
        db "FACTORYS"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "ENEMY   "
        db CMD_NEXT_LINE
        db "WARBASES"
        db CMD_END
    ; Script end
    call La81d_draw_robot_strength
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #0137  ; ptr to the attributes of the first menu option
    ld a, 1  ; start at option 1
    ld e, 4  ; 3 options menu
    call Lacd7_right_hud_menu_control
    add a, ROBOT_ORDERS_DESTROY_ENEMY_ROBOTS - 1
    jr Labc8_capture_or_destroy_order_selected

Lab4e_give_capture_orders:
    call Ld2f6_clear_in_game_right_hud
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #04, #17
        db CMD_SET_ATTRIBUTE, #4f
        db "SEARCH &"
        db CMD_NEXT_LINE
        db " CAPTURE"
        db CMD_SET_POSITION, #08, #18
        db CMD_SET_ATTRIBUTE, #45
        db "SELECT"
        db CMD_NEXT_LINE
        db "TARGET"
        db CMD_SET_POSITION, #0c, #17
        db CMD_SET_ATTRIBUTE, #4d
        db "NEUTRAL "
        db CMD_NEXT_LINE
        db "FACTORYS"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "ENEMY   "
        db CMD_NEXT_LINE
        db "FACTORYS"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "ENEMY   "
        db CMD_NEXT_LINE
        db "WARBASES"
        db CMD_END
    ; Script end:
    call La81d_draw_robot_strength
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #0137  ; ptr to the attributes of the first menu option
    ld a, 1  ; start at option 1
    ld e, 4  ; 3 options menu
    call Lacd7_right_hud_menu_control
    add a, ROBOT_ORDERS_CAPTURE_NEUTRAL_FACTORIES - 1

Labc8_capture_or_destroy_order_selected:
    ld (ix + ROBOT_STRUCT_ORDERS), a
    cp ROBOT_ORDERS_DESTROY_ENEMY_FACTORIES
    jr c, Labd9_orders_executable
    cp ROBOT_ORDERS_CAPTURE_NEUTRAL_FACTORIES
    jr nc, Labd9_orders_executable
    ; Player has selected to destroy factories or warbases.
    ; For that purpose, the robot must be equipped with a nuclear weapon.
    ; Check if it does, and otherwise, just cancel the order:
    bit 6, (ix + ROBOT_STRUCT_PIECES)
    jr z, Labf1_orders_not_executable
Labd9_orders_executable:
    ld l, (ix + ROBOT_STRUCT_X)
    ld h, (ix + ROBOT_STRUCT_X + 1)
    push af
        xor a
        ld (Lfd51_current_robot_player_or_enemy), a
    pop af
    ld (ix + ROBOT_STRUCT_ORDERS_ARGUMENT), #ff
    call Lb34d_find_capture_or_destroy_target
    ld (ix + ROBOT_STRUCT_ORDERS_ARGUMENT), d
    jr nz, Labf5_order_assignment_done
Labf1_orders_not_executable:
    ld (ix + ROBOT_STRUCT_ORDERS), ROBOT_ORDERS_STOP_AND_DEFEND
Labf5_order_assignment_done:
    ld a, 120
    call Lccac_beep
    call Lad57_wait_until_no_keys_pressed
    jp La732_land_on_robot_internal


; --------------------------------    
; Combat mode menu loop.
Lac00_combat_mode:
    call Ld2f6_clear_in_game_right_hud
    call Ld42d_execute_ui_script
    ; Start script:
        db CMD_SET_POSITION, #04, #17
        db CMD_SET_ATTRIBUTE, #4d
        db "NUCLEAR "
        db CMD_NEXT_LINE
        db "    BOMB"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "FIRE    "
        db CMD_NEXT_LINE
        db " PHASERS"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "FIRE    "
        db CMD_NEXT_LINE
        db "MISSILES"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "FIRE    "
        db CMD_NEXT_LINE
        db "  CANNON"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "MOVE    "
        db CMD_NEXT_LINE
        db "   ROBOT"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "STOP    "
        db CMD_NEXT_LINE
        db "  COMBAT"
        db CMD_END
    ; End script:
    call La81d_draw_robot_strength
    ld a, 6  ; current option is the bottom
Lac81_combat_mode_loop:
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #0037
    ld e, 7  ; menu has 6 options
    call Lacd7_right_hud_menu_control
    cp 6  ; stop combat
    jp z, La732_land_on_robot_internal
    push af
        cp 5
        jr nz, Lac99_weapon_fire_selected
        call La941_direct_control_internal
    pop af
    jr Lac81_combat_mode_loop

Lac99_weapon_fire_selected:
        ld c, a
        ld b, a
        inc b
        ld a, (ix + ROBOT_STRUCT_PIECES)
Lac9f:
        rlca
        djnz Lac9f
        jr nc, Lacce_selected_weapon_not_present
    pop af
    cp 1
    jr nz, Lacb3_regular_weapon_fire
    ; nuclear bomb selected:
    push ix
    pop iy
    call Lb99f_fire_nuclear_bomb
    jp La812_exit_robot

Lacb3_regular_weapon_fire:
    ; Weapon to fire is in "c"
    push af
        ; The first bullet record is used only for "combat mode". So, we only need to check if the 
        ; first bullet is available:
        ld iy, Ld7d3_bullets
        ld a, (iy + 1)
        or a  ; If there is already a weapon in use, we cannot fire
        jr nz, Lacce_selected_weapon_not_present
        ld a, 5
        sub c
        call Lb6d6_weapon_fire
        call Lccbd_redraw_game_area
        call Lad62_increase_time
    pop af
    jp Lac81_combat_mode_loop

Lacce_selected_weapon_not_present:
    ld a, 250
    call Lccac_beep
    pop af
    jp Lac81_combat_mode_loop


; --------------------------------
; Loop for moving around the options on a right-hand-side hud menu.
; Input:
; - a: cursor position.
; - e: number of options in the menu
Lacd7_right_hud_menu_control:
    push af
        call Lad57_wait_until_no_keys_pressed
    pop af
    ld d, a
    ld c, COLOR_BRIGHT + COLOR_BLUE*PAPER_COLOR_MULTIPLIER + COLOR_YELLOW
    call Lad3c_set_attributes_for_menu_option
Lace2_right_hud_menu_control_loop:
    ld a, (ix + 1)  ; check if the robot is destroyed
    or a
    jr nz, Lacec_robot_not_destroyed  ; if the robot is not destroyed, continue
    pop hl  ; simulate a "ret"
    jp La812_exit_robot
Lacec_robot_not_destroyed:
    push hl
        call Ld37c_read_keyboard_joystick_input
    pop hl
    ld c, d  ; d still has the cursor position
    ld a, (Lfd0c_keyboard_state)
    bit 4, a  ; is "fire" pressed
    jr nz, Lad2f_menu_option_selected
    rrca
    and 6
    jr z, Lad1a_no_cursor_change  ; neither up nor down are pressed
    and 2  ; if pressing down, a = 2, otherwise, a = 0
    dec c  ; more cursor up
    add a, c  ; if we pressed down, a = option + 1, otherwise, option - 1
    jr z, Lad1a_no_cursor_change  ; if we pressed up and are at the top, no change
    cp e
    jr nc, Lad1a_no_cursor_change  ; if we pressed down and we are at the bottom, no change
    push af
        ld a, d
        ld c, COLOR_BRIGHT + COLOR_BLUE*PAPER_COLOR_MULTIPLIER + COLOR_CYAN
        call Lad3c_set_attributes_for_menu_option
    pop af
    ld d, a
    ld c, COLOR_BRIGHT + COLOR_BLUE*PAPER_COLOR_MULTIPLIER + COLOR_YELLOW
    call Lad3c_set_attributes_for_menu_option
    ld a, 20
    call Lccac_beep
Lad1a_no_cursor_change:
    push de
    push hl
        ; Advance on game tick:
        call Lb0ca_update_robots_bullets_and_ai
        call Lccbd_redraw_game_area
        call Lb048_update_radar
        call Lad62_increase_time
        call La81d_draw_robot_strength
    pop hl
    pop de
    jr Lace2_right_hud_menu_control_loop
Lad2f_menu_option_selected:
    ld a, d  ; d still has the cursor position
    ld c, COLOR_BRIGHT + COLOR_BLUE*PAPER_COLOR_MULTIPLIER + COLOR_WHITE
    call Lad3c_set_attributes_for_menu_option
    ld a, 100
    call Lccac_beep
    ld a, d  ; d still has the cursor position
    ret


; --------------------------------
; Sets a 8x2 block in the attribute table to attribute "c". This is used to set the attributes of
; menu options in the right-hand-side hud.
; Input:
; - c: attribute value to set
; - a: which row to change attributes for (each row is 3 screen rows apart).
; - hl: attribute address of the first row
Lad3c_set_attributes_for_menu_option:
    ld b, a
    push de
    push hl
        ld de, 32*3
Lad42:
        add hl, de
        djnz Lad42
        ld b, 8
        call Lcbdb_set_attribute_loop  ; set 8 attribute positions to attribute "c"
        ld a, 24
        call Ld351_add_hl_a  ; go one row down
        ld b, 8
        call Lcbdb_set_attribute_loop  ; set 8 attribute positions to attribute "c"
    pop hl
    pop de
    ret


; --------------------------------
; Waits until the user is not pressing any key.
Lad57_wait_until_no_keys_pressed:
    push bc
    push hl
Lad59_wait_for_key_release_loop:
        call Ld37c_read_keyboard_joystick_input
        or a
        jr nz, Lad59_wait_for_key_release_loop
    pop hl
    pop bc
    ret


; --------------------------------
; - increases time by 5 minutes, and checks if a whole day has passed, to give resources to the
;   players
Lad62_increase_time:
    call Ld358_random
    ld hl, Lfd35_minutes
    ld a, (hl)
    add a, 5  ; add 5 minutes
    ld (hl), a
    cp 60
    jr nz, Lad85_increase_time_done
    ld (hl), 0  ; reset minutes
    inc hl
    inc (hl)  ; increase hour
    ld a, (hl)
    cp 24
    jr nz, Lad85_increase_time_done
    ld (hl), 0  ; reset hour
    ld hl, (Lfd37_days)
    inc hl  ; increase days
    ld (Lfd37_days), hl
    call Lae38_gain_day_resources
Lad85_increase_time_done:
    call Ld42d_execute_ui_script
    ; Start script:
        db CMD_SET_POSITION, #00, #1b
        db CMD_SET_SCALE, #00
        db CMD_SET_ATTRIBUTE, #57
        db CMD_END
    ; End script:
    ld hl, (Lfd37_days)
    call Ld3f3_render_16bit_number
    call Ld470_execute_command_3_next_line
    ld a, (Lfd36_hours)
    call Ld3ec_render_8bit_number_with_leading_zeroes
    ld a, 46
    call Ld427_draw_character_saving_registers
    ld a, (Lfd35_minutes)
    call Ld3ec_render_8bit_number_with_leading_zeroes
    call Lae6b_game_over_check
    push iy
        ld iy, Lfd70_warbases
        ld b, N_WARBASES + N_FACTORIES
        ld c, 0  ; c keeps track of how many captures happened this cycle
Ladb7_building_loop:
        ld l, (iy + BUILDING_STRUCT_X)
        ld h, (iy + BUILDING_STRUCT_X + 1)
        ld a, (iy + BUILDING_STRUCT_Y)
        call Lcca6_compute_map_ptr
        bit 6, (hl)  ; check if building is still there
        jr nz, Ladcd_something_in_front_of_it
        ld (iy + BUILDING_STRUCT_TIMER), 0
        jr Lae05_next_building
Ladcd_something_in_front_of_it:
        inc (iy + BUILDING_STRUCT_TIMER)
        ld a, (iy + BUILDING_STRUCT_TIMER)
        cp BUILDING_CAPTURE_TIME
        jr c, Lae05_next_building
        ; Something has been in front of the factory for BUILDING_CAPTURE_TIME cycles, capture!
        ld (iy + BUILDING_STRUCT_TIMER), 0
        push bc
            push iy
                call Lcdd8_get_robot_at_ptr
                ld a, (iy + ROBOT_STRUCT_CONTROL)
                rlca
                and 1
                ld e, a  ; here e has the robot owner (0 = player, 1 = enemy AI)
            pop iy
            ld a, b  ; if b == 0, no robot was found
            or a
            jr z, Lae04_next_building_pop
        pop bc
        inc c
        push bc
            ld a, N_FACTORIES + N_WARBASES
            sub b
            cp 4
            jr nc, Ladfe_factory
            ld b, e
            call Lbb86_assign_warbase_to_player  ; warbase captured!
            jr Lae04_next_building_pop
Ladfe_factory:
            sub 4
            ld b, e
            call Lbb61_assign_factory_to_player  ; factory captured!
Lae04_next_building_pop:
        pop bc
Lae05_next_building:
        ; next building (as BUILDING_STRUCT_SIZE == 5):
        inc iy
        inc iy
        inc iy
        inc iy
        inc iy
        djnz Ladb7_building_loop
    pop iy
    ld a, c  ; "c" has the number of buildings captured this cycle.
    or a
    jr z, Lae1d_no_new_captures
    call Lbb09_update_players_warbase_and_factory_counts
    call Ld293_update_stats_in_right_hud
Lae1d_no_new_captures:
    ld a, (Lfd34_n_interrupts_this_came_cycle)
    cp MIN_INTERRUPTS_PER_GAME_CYCLE
    jr c, Lae1d_no_new_captures  ; Loop to make sure games does not run too fast
    xor a
    ld (Lfd34_n_interrupts_this_came_cycle), a
    ret


; --------------------------------
; Unused/unreachable code:
; - I did not find anywhere in the code that could jump here. It could be some left-over code from
;   a previous version of the game.
; - It does not make sense to jump to the BIOS address #04b0 from this game, in any case, since it 
;   contains BASIC-related code. So, this code can be removed.
Lae29:
    ld a, INTERFACE2_JOYSTICK_PORT_MSB
    in a, (ULA_PORT)  ; read the interface2 joystick state
    and #18  ; button 1 or "up"
    ret nz
    ld hl, La600_start
    push hl
    di
    jp #04b0


; --------------------------------
; Update the resources each player has adding their daily gains, and updates the hud.
Lae38_gain_day_resources:
    ld hl, Lfd22_player1_resource_counts
    ld de, Lfd3a_player1_base_factory_counts
    call Lae4e_gain_day_resources_player
    ld hl, Lfd4a_player2_resource_counts
    ld de, Lfd42_player2_base_factory_counts
    call Lae4e_gain_day_resources_player
    call Ld293_update_stats_in_right_hud
    ret


; --------------------------------
; - adds 5 times the number of bases to the general resources
; - adds 2 times the number of factories of each type to the part-specific resources
; input:
; - de: pointer to the # of bases and factories of a given player
; - hl: pointer to the resources of a given player
Lae4e_gain_day_resources_player:
    ld a, (de)
    ld c, a
    add a, a
    add a, a
    add a, c  ; a = (de)*5
    call Lae62_add_limit_100  ; (hl) += (de)*5
    ld b, 6
Lae58_factory_loop:
    inc hl
    inc de
    ld a, (de)
    add a, a
    call Lae62_add_limit_100
    djnz Lae58_factory_loop
    ret


; --------------------------------
; Adds a to (hl), keeping the result smaller than 100
Lae62_add_limit_100:
    add a, (hl)
    cp 100
    jr c, Lae69_smaller_than_100
    ld a, 99
Lae69_smaller_than_100:
    ld (hl), a
    ret


; --------------------------------
; Checks if one of the players does not have any bases left,
; and shows the victory or defeat messages.
Lae6b_game_over_check:
    ld a, (Lfd42_player2_base_factory_counts)
    or a
    jr z, Laeb1_game_over_victory
    ld a, (Lfd3a_player1_base_factory_counts)
    or a
    ret nz
    ; Game over defeat:
    call Laf00_set_default_hud_and_empty_interrupt
    call Ld42d_execute_ui_script
    ; script start:
        db CMD_SET_POSITION, 22, 0
        db CMD_SET_ATTRIBUTE, 69
        db "YOU HAVE NO BASES LEFT"
        db CMD_NEXT_LINE
        db "BETTER LUCK NEXT TIME!"
        db CMD_END
    ; script end:
    jr Laeea_game_over_message_drawn
Laeb1_game_over_victory:
    call Laf00_set_default_hud_and_empty_interrupt
    call Ld42d_execute_ui_script
    ; script start:
        db CMD_SET_POSITION, 22, 0
        db CMD_SET_ATTRIBUTE, 69
        db " INSIGNIANS DESTROYED "
        db CMD_NEXT_LINE
        db "    YOU HAVE WON !    "
        db CMD_END
    ; script end:
Laeea_game_over_message_drawn:
    ; Produce a sound, wait for player to press some key, and restart the game.
    ld a, 250
    call Lccac_beep
    ld b, 100  ; wait 2 seconds
Laef1_wait_loop:
    halt
    djnz Laef1_wait_loop
    call Lad57_wait_until_no_keys_pressed
Laef7_wait_for_any_key:
    call Ld37c_read_keyboard_joystick_input
    or a
    jr z, Laef7_wait_for_any_key
    jp La600_start

Laf00_set_default_hud_and_empty_interrupt:
    xor a
    ld (Lfd39_current_in_game_right_hud), a
    call Ld2f6_clear_in_game_right_hud  ; Potential optimization: not needed, as this is already 
                                        ; called in the function below
    call Ld1e5_draw_in_game_right_hud
    ld hl, Ld59c_empty_interrupt
    ld (Lfdfe_interrupt_pointer), hl
    ret


; --------------------------------
; Controls the player ship using keyboard.
Laf11_player_ship_keyboard_control:
    call Lb01d_remove_player_from_map
    ; If the player is pressing up/down, reduce the effect of Lfd30_player_elevate_timer: 
    ld a, (Lfd0c_keyboard_state)
    and #0c  ; down/up
    jr z, Laf25_player_ship_keyboard_control_x  ; Potential optimization: the following lines 
                                                ; implement a random behavior (reduce elevate timer 
                                                ; if you are pressing up/down) that can be removed.
    ld a, (Lfd30_player_elevate_timer)
    or a
    jr z, Laf25_player_ship_keyboard_control_x
    dec a
    ld (Lfd30_player_elevate_timer), a

Laf25_player_ship_keyboard_control_x:
    ld a, (Lfd0c_keyboard_state)
    and #03
    jr z, Laf77_player_ship_keyboard_control_y  ; if left/right are not pressed
    cp 3
    jr z, Laf77_player_ship_keyboard_control_y  ; if left/right are pressed simultaneously
    ld hl, (Lfd0e_player_x)
    rrca
    jr c, Laf42_move_right
    ; Move left:
    ld a, h
    or a
    jr nz, Laf3f
    ld a, l
    cp MIN_PLAYER_X
    jr z, Laf77_player_ship_keyboard_control_y
Laf3f:
    dec hl
    jr Laf4c_move_player_if_no_collision
Laf42_move_right:
    ld a, h
    or a
    jr z, Laf4b
    ld a, l
    cp MAX_PLAYER_X - 256
    jr z, Laf77_player_ship_keyboard_control_y
Laf4b:
    inc hl
Laf4c_move_player_if_no_collision:
    ld a, (Lfd0d_player_y)
    call Lb052_check_player_collision
    jr c, Laf57_collision
    ld (Lfd0e_player_x), hl
Laf57_collision:
    ; See if we need to scroll the map:
    ld hl, (Lfd0e_player_x)
    ld de, (Lfd0a_scroll_x)
    xor a
    sbc hl, de
    ld a, l
    cp 13  ; player in the left screen edge
    jr nz, Laf67_no_scroll_left
    dec de
Laf67_no_scroll_left:
    cp 22  ; player in the right screen edge
    jr nz, Laf6c_no_scroll_right
    inc de
Laf6c_no_scroll_right:
    ld (Lfd0a_scroll_x), de
    ld hl, Ldd00_map
    add hl, de
    ld (Lfd06_scroll_ptr), hl

Laf77_player_ship_keyboard_control_y:
    ld a, (Lfd0d_player_y)
    ld c, a
    ld a, (Lfd0c_keyboard_state)
    rrca
    rrca
    and #03
    jr z, Lafa2_player_ship_keyboard_control_altitude  ; up/down not pressed
    cp 3
    jr z, Lafa2_player_ship_keyboard_control_altitude  ; up/down pressed simultaneously
    rrca
    jr nc, Laf8c_no_move_down  ; no move down
    inc c
Laf8c_no_move_down:
    rrca
    jr nc, Laf90_no_move_up
    dec c
Laf90_no_move_up:
    ld a, c
    and #0f
    jr z, Lafa2_player_ship_keyboard_control_altitude  ; do not go beyond map borders
    ld hl, (Lfd0e_player_x)
    ld b, a
    call Lb052_check_player_collision
    jr c, Lafa2_player_ship_keyboard_control_altitude  ; collision
    ld a, b
    ld (Lfd0d_player_y), a

Lafa2_player_ship_keyboard_control_altitude:
    ld a, (Lfd30_player_elevate_timer)
    or a
    jr z, Lafae_no_auto_elevate
    dec a
    ld (Lfd30_player_elevate_timer), a
    jr Lafb5_elevate
Lafae_no_auto_elevate:
    ld a, (Lfd0c_keyboard_state)
    and #10
    jr z, Lafc3_gravity
Lafb5_elevate:
    ld a, (Lfd10_player_altitude)
    cp MAX_PLAYER_ALTITUDE
    jr nc, Lafdb_continue
    add a, 2
    ld (Lfd10_player_altitude), a
    jr Lafdb_continue

Lafc3_gravity:
    ld a, (Lfd10_player_altitude)
    dec a  ; Player ship falls with gravity
    jp m, Lafdb_continue
    ld b, a
    ld a, (Lfd0d_player_y)
    ld hl, (Lfd0e_player_x)
    call Lb052_check_player_collision
    ld a, b
    cp c
    jr c, Lafdb_continue  ; collision when going down
    ld (Lfd10_player_altitude), a

Lafdb_continue:
    call Lafe6_radar_scroll
    ld hl, Lfd1e_player_visible_in_radar  ; Potential optimization: are these last lines needed? (
                                          ; this is already done in "Lb048_update_radar" each 
                                          ; cycle, so, maybe this just does even more blinking).
    inc (hl)
    call Lb024_add_player_to_map_and_update_radar  ; Potential optimization: tail recursion.
    ret


; --------------------------------
; Check if we need to scroll the radar screen due to player movement.
Lafe6_radar_scroll:
    ld hl, (Lfd0e_player_x)
    ld a, (Lfd1b_radar_scroll_x_tile)
    ld c, a
    ld a, l
    rr h
    rra
    srl a
    srl a  ; a = (Lfd0e_player_x) / 8
    sub c  ; c = (Lfd0e_player_x) / 8 - (Lfd1b_radar_scroll_x_tile)
    cp 2  ; if we are in the left-edge, scroll left
    jr c, Lafff_radar_scroll_left
    cp 14  ; if we are in the right-edge, scroll right
    jr nc, Lb005_radar_scroll_right
    ret
Lafff_radar_scroll_left:
    ld a, c
    sub 8
    ret m
    jr Lb00b_update_radar_scroll
Lb005_radar_scroll_right:
    ld a, c
    add a, 8
    cp 56
    ret z
Lb00b_update_radar_scroll:
    ld (Lfd1b_radar_scroll_x_tile), a
    add a, a
    add a, a
    ld l, a
    ld h, 0
    add hl, hl
    ld (Lfd1c_radar_scroll_x), hl
    ld a, 1
    ld (Lfd52_update_radar_buffer_signal), a
    ret


; --------------------------------
; Removes the player from the map (bit 7), and then draws the player in the radar view.
Lb01d_remove_player_from_map:
    call Lcca0_compute_player_map_ptr
    res 7, (hl)  ; mark player is no longer here
    jr Lb036_flicker_player_in_radar


; --------------------------------
; Marks that the player is in the map (bit 7), and
; also updates the radar buffers with buildings/robots and player.
Lb024_add_player_to_map_and_update_radar:
    call Lcca0_compute_player_map_ptr
    set 7, (hl)  ; mark player is here
Lb029_update_radar_view_if_necessary:
    ; Update the radar view if necessary:
    ld a, (Lfd52_update_radar_buffer_signal)
    or a
    jr z, Lb036_flicker_player_in_radar
    call Ld5f8_update_radar_buffers
    xor a
    ld (Lfd52_update_radar_buffer_signal), a
Lb036_flicker_player_in_radar:
    ld a, (Lfd1e_player_visible_in_radar)
    and 1
    ret z  ; Do not draw player in radar
    ld hl, (Lfd0e_player_x)
    ld a, (Lfd0d_player_y)
    ld c, a
    ld b, 0
    jp Ld65a_flip_2x2_radar_area


; --------------------------------
; Increments whether the player is visible in the radar or not, and updates the radar.
Lb048_update_radar:    
    call Lb036_flicker_player_in_radar
    ld hl, Lfd1e_player_visible_in_radar
    inc (hl)
    jp Lb029_update_radar_view_if_necessary


; --------------------------------
; Checks whether there would be a collision with the player altitude in a 3x3 area
; centered around a given set of coordinates:
; Input:
; - hl: x
; - a: y
; Return:
; - carry flag: set for collision, unset for no collision.
Lb052_check_player_collision:
    push hl
        call Lcca6_compute_map_ptr
        ex de, hl
        ld c, 0
        call Lb096_get_map_altitude_including_robots_and_decorations
        inc de  ; x += 1
        call Lb096_get_map_altitude_including_robots_and_decorations
        dec d
        dec d  ; y -= 1
        call Lb096_get_map_altitude_including_robots_and_decorations
        dec de  ; x -= 1
        call Lb096_get_map_altitude_including_robots_and_decorations
        dec de  ; x -= 1
        call Lb099_get_robot_or_decoration_altitude
        inc d  
        inc d  ; y += 1
        call Lb099_get_robot_or_decoration_altitude
        inc d
        inc d  ; y += 1
        ld a, d
        cp #fd  ; edge of the map
        jr nc, Lb084
        call Lb099_get_robot_or_decoration_altitude
        inc de  ; x += 1
        call Lb099_get_robot_or_decoration_altitude
        inc de  ; x += 1
        call Lb099_get_robot_or_decoration_altitude
Lb084:
        ld a, (Lfd10_player_altitude)
        cp c
    pop hl
    ret


; --------------------------------
; Gets the altitude of a position in the map, and if it is higher
; than the current of value in "c", it gets updated.
; Input:
; - de: map pointer
; Output:
; - a: map altitude
; - c: max of "c" and map altitude in "de".
Lb08a_get_map_altitude:
    ld a, (de)
    and #1f
    ld hl, Ld7bc_map_piece_heights
    call Ld351_add_hl_a
    ld a, (hl)
    jr Lb0ab_max_of_a_and_c


; --------------------------------
; Gets the altitude at a particular position, including robots and decorations.
; Input:
; - de: map pointer
; - c: initial altitude
; Output:
; - c: max of "c" and map altitude in "de" (including robots and decorations).
Lb096_get_map_altitude_including_robots_and_decorations:
    call Lb08a_get_map_altitude
Lb099_get_robot_or_decoration_altitude:
    ld h, d
    ld l, e
    bit 6, (hl)
    ret z
    push bc
        call Lcdd8_get_robot_at_ptr
        jr nz, Lb0b0_get_decoration_altitude
    pop bc
    ld a, (iy + ROBOT_STRUCT_HEIGHT)
    add a, (iy + ROBOT_STRUCT_ALTITUDE)
    ; jp Lb0ab_max_of_a_and_c


; --------------------------------
; c = max(c, a)
Lb0ab_max_of_a_and_c:
    cp c
    jr c, Lb0af_c_larger
    ld c, a
Lb0af_c_larger:
    ret


; --------------------------------
; Gets the altitude of a decoration (like a "flag") if present.
; Input:
; - de: map pointer
; - c: initial altitude
; Output:
; - c: max of "c" and decoration altitude in "de" if present.
Lb0b0_get_decoration_altitude:
        call Lcdf5_find_building_decoration_with_ptr
    pop bc
    ret nz
    ld a, (iy + BUILDING_DECORATION_STRUCT_TYPE)
    ld hl, Lb0c1_decoration_altitudes
    call Ld351_add_hl_a
    ld a, (hl)
    jr Lb0ab_max_of_a_and_c

Lb0c1_decoration_altitudes:
    db #0f  ; warbase "H"
    db #16, #15, #15, #16, #16, #16  ; pieces on top of factories
    db #19, #19  ; flags


; --------------------------------
; Executes one update cycle for each robot and bullet in the game.
Lb0ca_update_robots_bullets_and_ai:
    call Lb7f4_update_enemy_ai
    ld b, MAX_ROBOTS_PER_PLAYER * 2
    ld iy, Lda00_player1_robots
Lb0d3_robot_update_loop:
    push bc
        ld a, (iy + 1)
        or a
        call nz, Lb0fa_robot_update  ; If robot is not destroyed, execute one update cycle
        ld de, ROBOT_STRUCT_SIZE
        add iy, de
    pop bc
    djnz Lb0d3_robot_update_loop
    ld iy, Ld7d3_bullets  
    ld b, MAX_BULLETS
Lb0e9_bullet_update_loop:
    push bc
        ld a, (iy + 1)
        or a
        call nz, Lb70d_bullet_update  ; If there is a bullet, execute one update cycle
        ld de, BULLET_STRUCT_SIZE
        add iy, de
    pop bc
    djnz Lb0e9_bullet_update_loop
    ret


; --------------------------------
; Update cycle of a robot, checking if it has to be destroyed or not.
Lb0fa_robot_update:
    ld a, (iy + ROBOT_STRUCT_STRENGTH)
    or a
    jr z, Lb116_robot_destroyed
    jp p, Lb154_robot_ai_update
    ; negative energy: robot is destroyed, so we are just going to make it blink
    inc (iy + ROBOT_STRUCT_STRENGTH)
    ld l, (iy + ROBOT_STRUCT_MAP_PTR)
    ld h, (iy + ROBOT_STRUCT_MAP_PTR + 1)
    and 1
    jr nz, Lb113
    res 6, (hl)  ; blink out
    ret
Lb113:
    set 6, (hl)  ; blink in
    ret
Lb116_robot_destroyed:
    ld l, (iy + ROBOT_STRUCT_MAP_PTR)
    ld h, (iy + ROBOT_STRUCT_MAP_PTR + 1)
    res 6, (hl)  ; remove the mark in the map
    ; Check if there is something in the map or not. If there is nothing in the  map,
    ; we will add some random garbage.
    ld a, (hl)
    inc hl
    or (hl)
    dec h
    dec h
    or (hl)
    dec hl
    or (hl)
    inc h
    inc h
    and #3f
    jr nz, Lb136_map_not_empty  ; There is something in the map
    call Ld358_random
    and 1
    add a, 6
    call Lbd91_add_element_to_map  ; Add some debris to the map
Lb136_map_not_empty:
    ld l, (iy + ROBOT_STRUCT_X)
    ld h, (iy + ROBOT_STRUCT_X + 1)
    ld c, (iy + ROBOT_STRUCT_Y)
    ld a, (iy + ROBOT_STRUCT_CONTROL)
    rlca
    and 1
    ld b, a  ; b = 0 if it's a player robot, and b = 1 if it's an enemy AI robot.
    call Ld65a_flip_2x2_radar_area  ; remove robot out of the map
    ld (iy + 1), 0  ; mark the robot as removed
    call Lbb40_count_robots
    call Ld293_update_stats_in_right_hud  ; Potential optimization: tail recursion.
    ret


; --------------------------------
; Update cycle for robots behavior.
; Input:
; - iy: robot ptr.
Lb154_robot_ai_update:
    ld a, (iy + ROBOT_STRUCT_CONTROL)
    cp ROBOT_CONTROL_PLAYER_LANDED
    ret z  ; If the player has landed on top of the robot, do not update
    
    rlca
    and 1
    ld (Lfd51_current_robot_player_or_enemy), a
    dec (iy + ROBOT_STRICT_CYCLES_TO_NEXT_UPDATE)
    ret nz  ; if we do not yet need to update this robot, skip

    ld l, (iy + ROBOT_STRUCT_MAP_PTR)
    ld h, (iy + ROBOT_STRUCT_MAP_PTR + 1)
    res 6, (hl)  ; remove the mark of this robot in the map for now
    push hl
        ld l, (iy + ROBOT_STRUCT_X)
        ld h, (iy + ROBOT_STRUCT_X + 1)
        ld c, (iy + ROBOT_STRUCT_Y)
        ld a, (iy + ROBOT_STRUCT_CONTROL)
        rlca
        and 1
        ld b, a  ; potential optimization: this was already computed above.
        call Ld65a_flip_2x2_radar_area
    pop hl
    call Lb513_get_robot_movement_possibilities
    ld a, (iy + ROBOT_STRUCT_CONTROL)
    cp ROBOT_CONTROL_DIRECT_CONTROL
    jp z, Lb450_robot_control_direct_control
    push bc
        call Lb626_check_directions_with_enemy_robots
    pop bc
    ld a, e
    or a
    jr z, Lb1e9_no_enemy_robots_in_sight

    and (iy + ROBOT_STRUCT_DIRECTION)
    jr z, Lb1d7_no_enemy_robots_in_the_current_direction
    ; If we are here, there is an enemy robot just ahead
    and c
    ld (iy + ROBOT_STRUCT_DESIRED_MOVE_DIRECTION), a
    push ix
    push iy
        push iy
        pop ix
        call Lb6b8_find_new_bullet_ptr
        jr nz, Lb1cd_do_not_fire
        call Ld358_random  ; pick one of our weapons at random
        and #38  ; bits corresponding to weapons (cannon, missiles, phaser)
        and (ix + ROBOT_STRUCT_PIECES)
        jr z, Lb1cd_do_not_fire
        ; Get the index of the lowest bit in "a" that is 1, corresponding to a weapon piece:
        ld c, 6
Lb1b7:
        dec c
        rlca
        jr nc, Lb1b7
        ld a, c
        call Lb6d6_weapon_fire
    pop iy
    pop ix
    ld (iy + ROBOT_STRUCT_DESIRED_MOVE_DIRECTION), 0
    ld (iy + ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING), 1
    jr Lb20d_move_robot
Lb1cd_do_not_fire:
    pop iy
    pop ix
    ld (iy + ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING), 1
    jr Lb20d_move_robot
Lb1d7_no_enemy_robots_in_the_current_direction:
    ld c, e
    ld b, c
    call Lb505_check_number_of_directions_is_one
    call nz, Lb33e_pick_direction_at_random
    ld (iy + ROBOT_STRUCT_DESIRED_MOVE_DIRECTION), c
    ld (iy + ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING), 2
    jp Lb20d_move_robot
Lb1e9_no_enemy_robots_in_sight:
    dec (iy + ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING)
    jp m, Lb1f5_move_in_a_new_direction
    ld a, (iy + ROBOT_STRUCT_DESIRED_MOVE_DIRECTION)
    and c
    jr nz, Lb20d_move_robot
Lb1f5_move_in_a_new_direction:
    ; pick a random number of steps:
    call Ld358_random
    and 3
    add a, 3
    ld (iy + ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING), a
    call Lb505_check_number_of_directions_is_one
    call nc, Lb222_choose_direction_to_move
    ld a, (iy + ROBOT_STRUCT_MAP_PTR + 1)
    or a
    ret z
    ld (iy + ROBOT_STRUCT_DESIRED_MOVE_DIRECTION), c

Lb20d_move_robot:
    ld a, (iy + ROBOT_STRUCT_DESIRED_MOVE_DIRECTION)
    ld l, (iy + ROBOT_STRUCT_X)
    ld h, (iy + ROBOT_STRUCT_X + 1)
    ld b, (iy + ROBOT_STRUCT_Y)
    call Lb471_move_robot_one_step_in_desired_direction
    call Lb5f3_determine_speed_based_on_terrain
    jp Lcc7c_set_robot_position


; --------------------------------
; Chooses a direction for a robot to move to, considering the orders and target.
; Input:
; - iy: robot ptr.
; - c: one-hot representation of the directions we can to move the robot in.
; Output:
; - c: direction to move.
Lb222_choose_direction_to_move:
    ld b, c
    ld a, (iy + ROBOT_STRUCT_ORDERS)
    or a
    jr nz, Lb22b_choose_direction_to_move_continue
    ld c, a  ; if orders are "stop and defend", just set direction = 0
    ret

Lb22b_choose_direction_to_move_continue:
    cp ROBOT_ORDERS_DESTROY_ENEMY_ROBOTS
    jp c, Lb326_choose_direction_orders_with_possible_directions
    jr nz, Lb289_choose_direction_orders_with_building_targets

    ; Destroy enemy robots orders:
    ld a, (iy + ROBOT_STRUCT_ORDERS_ARGUMENT)
    or a
    jp m, Lb258_find_new_robot_target
    call Lb3f9_find_orders_target_robot_ptr
    inc hl
    ld a, (hl)
    or a
    jr z, Lb258_find_new_robot_target  ; if our current target was already destroyed, pick a new one
    inc hl
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a  ; hl now is target robot "x"
    ld e, (iy + ROBOT_STRUCT_X)
    ld d, (iy + ROBOT_STRUCT_X + 1)
    call Lb3ca_distance_from_hl_to_de
    ld a, h
    or a
    jr nz, Lb258_find_new_robot_target  ; If robot target is too far, pick a new one.
    ld a, l
    cp 50
    jr c, Lb26d_choose_direction_to_target_robot  ; If robot target is too far, pick a new one.
Lb258_find_new_robot_target:
    ld l, (iy + ROBOT_STRUCT_X)
    ld h, (iy + ROBOT_STRUCT_X + 1)
    ld (iy + ROBOT_STRUCT_ORDERS_ARGUMENT), #ff
    push bc
        call Lb41d_find_nearest_opponent_robot
    pop bc
    ld (iy + ROBOT_STRUCT_ORDERS_ARGUMENT), d
    jp z, Lb33e_pick_direction_at_random  ; if no nearest robot, pick a direction at random.

Lb26d_choose_direction_to_target_robot:
    call Lb3f9_find_orders_target_robot_ptr
    inc hl
    inc hl
    ld e, (hl)  
    inc hl
    ld d, (hl)  ; "de" now has the target robot "x"
    inc hl
    ld a, (iy + ROBOT_STRUCT_Y)
    sub (hl)  
    ld b, a  ; "b" now has "y" - "target robot y"
    ld l, (iy + ROBOT_STRUCT_X)
    ld h, (iy + ROBOT_STRUCT_X + 1)
    xor a
    sbc hl, de  ; "hl" now has "x" - "target robot x"
    ld d, a  ; "d" = 0 to indicate same x ("Lb2d5_choose_direction_to_target_coordinates" will 
             ; overwrite if they are not).
    jr z, Lb2dc_choose_direction_to_target_coordinates_x_alread_considered
    jr Lb2d5_choose_direction_to_target_coordinates

Lb289_choose_direction_orders_with_building_targets:
    ; If we are here, orders are to capture/destroy some building.
    call Lb3d5_prepare_robot_order_building_target_search
    ld a, (iy + ROBOT_STRUCT_ORDERS_ARGUMENT)
    ld b, a
    add a, a
    add a, a
    add a, b  ; a *= BUILDING_STRUCT_SIZE
    call Ld351_add_hl_a  ; hl has the pointer to the target
    ld a, (hl)
    and #e0  ; keep just the flags
    cp e  ; see if the flags match the orders target
    jr z, Lb2bb_choose_direction_to_target_building
    ; Pick a new target building:
    ld a, (iy + ROBOT_STRUCT_ORDERS)
    push bc
        ld l, (iy + ROBOT_STRUCT_X)
        ld h, (iy + ROBOT_STRUCT_X + 1)
        call Lb34d_find_capture_or_destroy_target
    pop bc
    jr nz, Lb2b8_target_found
    ; We could not find any target:
    ld c, 0
    bit 7, (iy + ROBOT_STRUCT_CONTROL)
    ret z
    ; if it's an enemy AI controlled robot, switch to targeting player robots:
    ld (iy + ROBOT_STRUCT_ORDERS), ROBOT_ORDERS_DESTROY_ENEMY_ROBOTS
    ret

Lb2b8_target_found:
    ld (iy + ROBOT_STRUCT_ORDERS_ARGUMENT), d
Lb2bb_choose_direction_to_target_building:
    ; Calculate the relative target coordinates:
    dec hl
    ld a, (iy + ROBOT_STRUCT_Y)
    sub (hl)
    ld b, a  ; "b" now has "y" - "target robot y"
    dec hl
    ld d, (hl)
    dec hl
    ld e, (hl)
    ld l, (iy + ROBOT_STRUCT_X)
    ld h, (iy + ROBOT_STRUCT_X + 1)
    xor a
    sbc hl, de  ; "hl" now has "x" - "target robot x"
    ld d, a  ; "d" = 0 to indicate same x ("Lb2d5_choose_direction_to_target_coordinates" will 
             ; overwrite if they are not).
    jr z, Lb2dc_choose_direction_to_target_coordinates_x_alread_considered
    ld a, b
    sub 3
    ld b, a
Lb2d5_choose_direction_to_target_coordinates:
    ; At this point we have the relative position of the target to the robot in "hl", "b"
    ld a, h
    rrca
    and #03  ; a = (h/2) mod 4
    xor 2  ; flip the second bit
    ld d, a  ; d = 1 if difference in "x" is negative, d = 2 if difference is positive
Lb2dc_choose_direction_to_target_coordinates_x_alread_considered:
    ld a, b
    or a
    jr z, Lb2e8_target_directions_calculated
    ; different y:
    ; accumulate in "d" the good directions to go toward the target:
    rrca
    rrca
    and #0c
    xor 8
    or d
    ld d, a  ; d now has "1"s in the up/down directions pointing toward the target
Lb2e8_target_directions_calculated:
    ld a, d
    or a
    jr nz, Lb306_not_at_target
    ; We are at the target position:
    ld c, a
    ld a, (iy + ROBOT_STRUCT_ORDERS)
    cp ROBOT_ORDERS_DESTROY_ENEMY_FACTORIES
    jr c, Lb2f9_inconsistent_orders
    cp ROBOT_ORDERS_CAPTURE_NEUTRAL_FACTORIES
    jp c, Lb99f_fire_nuclear_bomb
Lb2f9_inconsistent_orders:
    ; If we reached here, something went wrong (we have orders ROBOT_ORDERS_DESTROY_ENEMY_ROBOTS, 
    ; but are exactly on target, which is weird, so, just keep moving)
    ld a, (iy + ROBOT_STRUCT_DIRECTION)
    cp 4
    ret z
    ld c, 4  ; desired direction is down, and go until collision, then reconsider.
    ld (iy + ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING), #ff
    ret
Lb306_not_at_target:
    ; get the absolute difference of the "x" difference:
    ld a, l
    or a
    jp p, Lb30e_x_diff_positive
    neg
    ld l, a
Lb30e_x_diff_positive:
    cp 8
    ld b, c
    ld a, d
    jr nc, Lb326_choose_direction_orders_with_possible_directions  ; if target is further than 8 
                                                                   ; positions away follow the 
                                                                   ; target directions.
    ; If we are closer than 8 cells (in "x") to the target, we will move at random until reaching 
    ; it:
    and c
    jr z, Lb33e_pick_direction_at_random  ; if we have no good directions, pick one at random
    ld b, a
    and #03
    jr z, Lb33e_pick_direction_at_random  ; If we cannot go left/right, pick a direction at random.
    ld a, l
    or a
    jr z, Lb33e_pick_direction_at_random  ; if we are at the same "x", pick a direction at random
    dec a  ; set the number of steps to keep walking to the distance to the target in "x" - 1
    ld (iy + ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING), a
    jr Lb33e_pick_direction_at_random

Lb326_choose_direction_orders_with_possible_directions:
    ; If we are here is that "a" has the good directions to move in.
    and #03
    ld d, a
    xor #fc  ; here we reverse the up/down directions, to try something different if we fail to 
             ; pick a direction.
    ld e, a
    ld a, c  ; c has the possible directions we can move in
    and d  ; if stop&defend, a = 0, if it's advance/retreat: a direction compatible with it if 
           ; available.
    jr z, Lb33e_pick_direction_at_random  ; if no direction compatible with orders, pick one at 
                                          ; random.
    ; Otherwise, try twice to pick a direction among the ones that are compatible:
    ld c, d
    call Ld358_random
    and d
    ret nz  ; first attempt
    call Ld358_random
    and d
    ret nz  ; second attempt
    ld a, b  ; b still has the available directions of movement
    and e
    ld b, a  ; now b has compatible directions (with up/down flipped). So, we pick one at random 
             ; from those:

Lb33e_pick_direction_at_random:
    ld c, b
    ; keep generating random numbers, and masking with the possible directions,
    ; until we get just 1 direction, and use it:
Lb33f_pick_direction_at_random_loop:
    call Ld358_random
    and c
    ld c, a
    call Lb505_check_number_of_directions_is_one
    ret z
    jr nc, Lb33f_pick_direction_at_random_loop
    ld c, b
    jr Lb33f_pick_direction_at_random_loop


; --------------------------------
; Finds the target for a capture or destroy order. This can be
; the index of a robot, or the index of a building.
; Input:
; - a: orders
; Output:
; - d: target.
; - z: no target found.
; - nz: target found.
Lb34d_find_capture_or_destroy_target:
    cp ROBOT_ORDERS_DESTROY_ENEMY_ROBOTS
    jp z, Lb41d_find_nearest_opponent_robot
    push af
        ex af, af'
    pop af
    call Lb411_prepare_nearest_robot_or_building_search_registers
    call Lb3d5_prepare_robot_order_building_target_search
Lb35b_building_loop:
    ld a, (hl)
    and #e0
    cp e  ; check if they match the order target flags
    call z, Lb36c_check_if_building_is_available_and_nearest_than_current_nearest
    ; next building:
    ld a, l
    add a, BUILDING_STRUCT_SIZE
    ld l, a
    inc c
    djnz Lb35b_building_loop
    ld a, d  ; d has the nearest building that was available as a target.
    inc a  ; check if we found a target (d == #ff means no target found).
    ret


; --------------------------------
; Given a building (index "c"), checks to make sure no other robot with the same
; orders as the current robot has that building as its target already. Then, if
; this is not the case, checks to see if this is closer than the previous target
; we had found. IF it is, set this building as the current target.
; Input:
; - a': orders
; - c: current building index
Lb36c_check_if_building_is_available_and_nearest_than_current_nearest:
    push iy
    push bc
    push de
            ex af, af'
                ld e, a  ; retrieve the orders
            ex af, af'
        ; Check if there is already another robot with the same orders, and that
        ; already has this target:
        ; Determine if we are searching over player or enemy robots:
        ld iy, Lda00_player1_robots
        ld a, (Lfd51_current_robot_player_or_enemy)
        or a
        jr z, Lb381_target_robots_ptr_set
        ld iy, Ldb80_player2_robots
Lb381_target_robots_ptr_set:
        ld b, MAX_ROBOTS_PER_PLAYER
Lb383:
        ld a, (iy + 1)
        or a
        jr z, Lb395_next_robot
        ld a, (iy + ROBOT_STRUCT_ORDERS)
        cp e  ; Check if robot has the same orders
        jr nz, Lb395_next_robot
        ld a, (iy + ROBOT_STRUCT_ORDERS_ARGUMENT)
        cp c  ; check if the other robot already has this building as the target
        jr z, Lb3ae_skip_building
Lb395_next_robot:
        push de
            ld de, ROBOT_STRUCT_SIZE
            add iy, de
        pop de
        djnz Lb383
    pop de
    pop bc
    pop iy
    ; If we reached this point, it means that there is no other robot that has
    ; this building as its target. See if it's closer than the current closest:
    push hl
        dec hl
        dec hl
        ld a, (hl)
        dec hl
        ld l, (hl)
        ld h, a
        call Lb3b3_check_if_nearer_than_current_nearest
    pop hl
    ret
Lb3ae_skip_building:
    pop de
    pop bc
    pop iy
    ret


; --------------------------------
; Check if the coordinate "hl" (x) is nearer than the current robot
; believed to be the nearest to the reference robot (only considering "x").
; Input:
; - hl: x coordinate to check
Lb3b3_check_if_nearer_than_current_nearest:
    push hl
    exx
        pop hl
        call Lb3ca_distance_from_hl_to_de  ; distance from "hl" to reference robot
        ld a, h
        cp b
        jr c, Lb3c3_new_closest
        jr nz, Lb3c8
        ld a, l
        cp c
        jr nc, Lb3c8
Lb3c3_new_closest:
        ld b, h  ; update the "closest distance"
        ld c, l
    exx
    ld d, c  ; update the index of the closest robot
    ret
Lb3c8:
    exx
    ret


; --------------------------------
; Returns the absolute value of |hl - de|.
Lb3ca_distance_from_hl_to_de:
    xor a
    sbc hl, de
    ret p
    sub l
    ld l, a
    ld a, 0
    sbc a, h
    ld h, a
    ret


; --------------------------------
; Given the orders of the current robot, prepares the registers to look for a potential
; target.
; Input:
; - a: robot orders
; Output:
; - hl: ptr to factories or warbases
; - b: # buildings to search 
; - e: target flags (whether we are looking for friendly, enemy or neutral buildings).
Lb3d5_prepare_robot_order_building_target_search:
    ld hl, Lfd84_factories + BUILDING_STRUCT_TYPE
    ld b, N_FACTORIES
    cp ROBOT_ORDERS_DESTROY_ENEMY_WARBASES
    jr z, Lb3e2_look_for_a_warbase
    cp ROBOT_ORDERS_CAPTURE_ENEMY_WARBASES
    jr nz, Lb3e7_continue
Lb3e2_look_for_a_warbase:
    ld hl, Lfd70_warbases + BUILDING_STRUCT_TYPE
    ld b, N_WARBASES
Lb3e7_continue:
    ld e, #20  ; bit 5 (indicates enemy)
    push af
        ld a, (Lfd51_current_robot_player_or_enemy)
        or a
        jr z, Lb3f2_player
        rlc e  ; changes to bit 6 (indicates player)
Lb3f2_player:
    pop af
    cp ROBOT_ORDERS_CAPTURE_NEUTRAL_FACTORIES
    ret nz
    ld e, 0  ; if we are looking for neutral buildings, set e to 0 (neither player nor enemy)
    ret


; --------------------------------
; Gets the target robot index, based on the orders argument.
; Input:
; - iy: robot
; Output:
; - hl: ptr to target robot
Lb3f9_find_orders_target_robot_ptr:
    ld de, Lda00_player1_robots
    ld a, (Lfd51_current_robot_player_or_enemy)
    or a
    jr nz, Lb405_target_is_player_1
    ld de, Ldb80_player2_robots
Lb405_target_is_player_1:
    ld a, (iy + ROBOT_STRUCT_ORDERS_ARGUMENT)
    add a, a
    add a, a
    add a, a
    ld l, a
    ld h, 0
    add hl, hl
    add hl, de  ; hl = Lda00_player1/2_robots + ROBOT_STRUCT_SIZE * argument
    ret


; --------------------------------
; Initializes some ghost registers for preparing to find the "closest" robot/building.
; - Copies "hl" to "de'" (x of the reference robot)
; - set "bc'" = 8192 (min distance)
; - c = 0  ; current robot/building we are checking
; - d = #ff  ; will store the index of the closest robot/building
Lb411_prepare_nearest_robot_or_building_search_registers:
    push hl
    exx
        pop de
        ld bc, 8192
    exx
    ld c, 0
    ld d, #ff
    ret


; --------------------------------
; Finds the opponent robot that is nearest to the current robot.
; Input:
; - iy: current robot ptr.
; Output:
; - d: nearest robot index.
; - z: no nearest robot.
; - nz: some nearest robot found.
Lb41d_find_nearest_opponent_robot:
    call Lb411_prepare_nearest_robot_or_building_search_registers
    push iy
        ; Choose either "Lda00_player1_robots" or "Ldb80_player2_robots", 
        ; depending on whether the current robot belongs to player or enemy AI.
        ld iy, Lda00_player1_robots  ; if current robot is enemy, search through 
                                     ; "Lda00_player1_robots"
        ld a, (Lfd51_current_robot_player_or_enemy)
        or a
        jr nz, Lb430
        ld iy, Ldb80_player2_robots  ; if current robot is player, search through 
                                     ; "Lda00_player2_robots"
Lb430:
        ld b, MAX_ROBOTS_PER_PLAYER
Lb432_loop_robot:
        ld a, (iy + 1)
        or a
        jr z, Lb441_next_robot
        ld l, (iy + ROBOT_STRUCT_X)
        ld h, (iy + ROBOT_STRUCT_X + 1)
        call Lb3b3_check_if_nearer_than_current_nearest
Lb441_next_robot:
        push de
            ld de, ROBOT_STRUCT_SIZE
            add iy, de
        pop de
        inc c  ; next robot index
        djnz Lb432_loop_robot
    pop iy
    ld a, d
    inc a
    ret


; --------------------------------
; Updates a robot while we are moving it in combat mode.
; Input:
; - iy: robot ptr.
; - c: possible move directions (along which there would be no collision).
Lb450_robot_control_direct_control:
    push bc
        call Ld37c_read_keyboard_joystick_input
    pop bc
    ld b, c
    cp (iy + ROBOT_STRUCT_DIRECTION)
    ; Since when we are requesting the robot to turn, collisions do not matter, we do not filter
    ; by collisions:
    jr nz, Lb45c_keyboard_input_different_from_current_robot_direction
    and c  ; we filter keyboard input keys by those directions we can actually move the robot in.
Lb45c_keyboard_input_different_from_current_robot_direction:
    ld c, a  ; "c" now has the directions we want to move the robot towards, and are possible.
    call Lb505_check_number_of_directions_is_one
    jr z, Lb467_only_one_direction
    ld a, (iy + ROBOT_STRUCT_DESIRED_MOVE_DIRECTION)  ; get the current desired direction
    and b  ; "b" still had the possible move directions.
    ld c, a  ; if we can still move in the desired, keep moving, otherwise, stop.
Lb467_only_one_direction:
    ld (iy + ROBOT_STRUCT_DESIRED_MOVE_DIRECTION), c
    ld a, c
    ld (Lfd0c_keyboard_state), a  ; overwrite the keyboard state with the filtered direction
    jp Lb20d_move_robot


; --------------------------------
; Moves the robot one step in the desired direction (if currently facing it), or rotates it if
; needed.
; Input:
; - a: robot desired move direction.
Lb471_move_robot_one_step_in_desired_direction:
    or a
    ret z  ; If robot does not want to move, return.
    cp (iy + ROBOT_STRUCT_DIRECTION)
    jr z, Lb495  ; if robot is facing the right direction, just move
    ; rotate robot:
    ld c, a
    or (iy + ROBOT_STRUCT_DIRECTION)
    cp #03
    jr nz, Lb486
    rlc c  ; because of the way they organized the direction bits, to rotate 90 degrees, we need to 
           ; shift the bits w positions. Potential optimization: all the direction code can be 
           ; greatly simplified if direction bits are reordered.
    rlc c
    jr Lb48e_new_direction_calculated
Lb486:
    cp #0c
    jr nz, Lb48e_new_direction_calculated
    rrc c  ; because of the way they organized the direction bits, to rotate 90 degrees, we need to 
           ; shift the bits w positions
    rrc c
Lb48e_new_direction_calculated:
    ; We now have the new robot direction:
    ld (iy + ROBOT_STRUCT_DIRECTION), c
    inc (iy + ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING)  ; since this was not a move, it does 
                                                             ; not count toward the # of steps we 
                                                             ; want to move.
    ret
Lb495:
    ; Make the robot actually advance:
    call Lb4b9_robot_advance
    call Lb5d6_map_altitude_2x2
    ld (iy + ROBOT_STRUCT_ALTITUDE), a
    ld a, (iy + ROBOT_STRUCT_CONTROL)  ; update the altitude of the robot based on the terrain 
                                       ; underneath.
    cp ROBOT_CONTROL_DIRECT_CONTROL
    ret nz
    ; If we are here it means the player is controlling the robot directly.
    push bc
    push hl
    push iy
        ; This just has the effect of making the player mimic the robot movement:
        call z, Laf11_player_ship_keyboard_control  ; Potential optimization: (not really an 
                                                    ; optimization), the "z," is not needed.
    pop iy
    pop hl
    pop bc
    ld a, (iy + ROBOT_STRUCT_HEIGHT)
    add a, (iy + ROBOT_STRUCT_ALTITUDE)
    ld (Lfd10_player_altitude), a
    ret


; --------------------------------
; Moves a robot in the direction it wants to move, and update the
; order parameters in case they were advance or retreat.
; Input:
; - a: desired move direction (one-hot encoding)
Lb4b9_robot_advance:
    rrca
    jr nc, Lb4c7_not_right
    ; move right:
    inc hl
    ld a, (iy + ROBOT_STRUCT_ORDERS)
    dec a
    jr z, Lb4f2_advance_in_direction_of_orders
    dec a
    jr z, Lb4de_advance_against_direction_of_orders
    ret

Lb4c7_not_right:
    rrca
    jr nc, Lb4d5_not_left
    ; move left:
    dec hl
    ld a, (iy + ROBOT_STRUCT_ORDERS)
    dec a
    jr z, Lb4de_advance_against_direction_of_orders
    dec a
    jr z, Lb4f2_advance_in_direction_of_orders
    ret

Lb4d5_not_left:
    rrca
    jr nc, Lb4da_not_down
    ; move down:
    inc b
    ret

Lb4da_not_down:
    rrca
    ret nc
    ; move up:
    dec b
    ret

Lb4de_advance_against_direction_of_orders:
    ; The robot moved against the direction it wants to go (e.g., its orders
    ; were "retreat", but it moved to the right). So, we increment the argument
    ; of the orders to compensate:
    ld a, (iy + ROBOT_STRUCT_CONTROL)
    cp ROBOT_CONTROL_DIRECT_CONTROL
    ret z
    inc (iy + ROBOT_STRUCT_ORDERS_ARGUMENT)
    ld a, (iy + ROBOT_STRUCT_ORDERS_ARGUMENT)
    cp 100
    ret c  ; do not go beyond 99 in the distance to travel.
    ld (iy + ROBOT_STRUCT_ORDERS_ARGUMENT), 99
    ret

Lb4f2_advance_in_direction_of_orders:
    ; The robot moved towards the direction it wants to go (e.g., its orders
    ; were "retreat", and it moved to the left). So, we decrement the argument
    ; of the orders to compensate:
    ld a, (iy + ROBOT_STRUCT_CONTROL)
    cp ROBOT_CONTROL_DIRECT_CONTROL
    ret z
    dec (iy + ROBOT_STRUCT_ORDERS_ARGUMENT)
    ret nz
    ; When the robot advances/retreats the desired number of miles, 
    ; switch to "stop & defend":
    ld (iy + ROBOT_STRUCT_ORDERS), ROBOT_ORDERS_STOP_AND_DEFEND
    ld (iy + ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING), 0
    ret


; --------------------------------
; Counts the number of bits in the lower nibble of "c" that are set to 1, and checks
; if there is only 1 such bit on.
; Input: 
; - c: one-hot representation of the directions we want to move the robot in.
Lb505_check_number_of_directions_is_one
Lb505_count_number_of_active_bits_in_the_lower_nibble:
    push bc
        ld b, 4  ; only consider the lower 4 bis
        xor a
Lb509_direction_loop:
        rr c
        adc a, 0  ; if the bit was set, increment a, otherwise do not increment.
        djnz Lb509_direction_loop
    pop bc
    cp 1  ; check that the number of bits set to 1 was just 1.
    ret


; --------------------------------
; Checks which directions can a robot move in, and in which it will collide.
; Input:
; - iy: robot ptr.
; Output:
; - c: lower 4 bits indicate if robot can move right, left, up, down.
Lb513_get_robot_movement_possibilities:
    ld c, 0
    ; Check if the player is above or below robot height, to see if the player
    ; is an obstacle or not.
    ld a, (Lfd10_player_altitude)
    sub (iy + ROBOT_STRUCT_HEIGHT)
    sub (iy + ROBOT_STRUCT_ALTITUDE)
    and 128  ; If the player is lower than the robot height, player is also an obstable
    or #40
    ld e, a  ; e contains a mask to check if a given position in the map is not walkable due to 
             ; player or another robot.
    ld a, (iy + ROBOT_STRUCT_PIECES)
    ld d, 8  ; if chassis is bipod, d = 8
    rrca
    jr c, Lb532
    ld d, 12  ; if chassis is tracks, d = 12
    rrca
    jr c, Lb532
    ld d, 15  ; if chassis is antigrav, d = 15
Lb532:
    push hl
        call Lb557_check_robot_collision_inc_x
    pop hl
    jr nz, Lb53b_collision_right
    set 0, c  ; mark that we can move to the right
Lb53b_collision_right:
    push hl
        call Lb56f_check_robot_collision_dec_x
    pop hl
    jr nz, Lb544_collision_left
    set 1, c  ; mark that we can move to the left
Lb544_collision_left:
    push hl
        call Lb58f_check_robot_collision_inc_y
    pop hl
    jr nz, Lb54d_collision_down
    set 2, c  ; mark that we can move down
Lb54d_collision_down:
    push hl
        call Lb5b1_check_robot_collision_dec_y
    pop hl
    jr nz, Lb556_up
    set 3, c  ; mark that we can move up
Lb556_up:
    ret


; --------------------------------
; Checks if a robot can walk to the right (incrementing x).
; Input:
; - hl: map pointer
; - d: 8 for bipod, 12 for tracks, and 15 for antigrav (the highest map element a robot can walk 
;      over).
; - e: mask of non-walkable elements (usually just #40 to indicate other robots are not walkable).
;      But it could be #c0 when the player is lower than the height of the robot in consideration,
;      to consider the player as an obstacle.
Lb557_check_robot_collision_inc_x:
    inc hl
    inc hl  ; x += 2
    dec h
    dec h  ; y -= 1
    call Lb5cd_robot_map_collision_internal
    ret nz  ; collision
    inc h  ; y += 1
    inc h
    call Lb5cd_robot_map_collision_internal
    ret nz  ; collision
    inc h  ; y += 1
    inc h
    ld a, h
    cp #fd  ; check if we are out of map bounds
    jr nc, Lb5c8_no_collision
    ld a, (hl)
    and e
    ret


; --------------------------------
; Checks if a robot can walk to the left (decrementing x).
; Input:
; - hl: map pointer
; - d: 8 for bipod, 12 for tracks, and 15 for antigrav (the highest map element a robot can walk 
;      over).
; - e: mask of non-walkable elements (usually just #40 to indicate other robots are not walkable).
;      But it could be #c0 when the player is lower than the height of the robot in consideration,
;      to consider the player as an obstacle.
Lb56f_check_robot_collision_dec_x:
    dec h  ; y -= 1
    dec h
    dec hl  ; x -= 1
    call Lb5cd_robot_map_collision_internal
    ret nz  ; collision
    dec hl  ; x -= 1
    ld a, (hl)
    and e
    ret nz  ; collision
    inc h  ; y += 1
    inc h
    ld a, (hl)
    and e
    ret nz  ; collision
    inc hl  ; x += 1
    call Lb5cd_robot_map_collision_internal
    ret nz  ; collision
    dec hl  ; x -= 1
    inc h
    inc h  ; y += 1
    ld a, h
    cp #fd  ; check if we are out of map bounds
    jr nc, Lb5c8_no_collision
    ld a, (hl)
    and e
    ret


; --------------------------------
; Checks if a robot can walk down (incrementing y).
; Input:
; - hl: map pointer
; - d: 8 for bipod, 12 for tracks, and 15 for antigrav (the highest map element a robot can walk 
;      over).
; - e: mask of non-walkable elements (usually just #40 to indicate other robots are not walkable).
;      But it could be #c0 when the player is lower than the height of the robot in consideration,
;      to consider the player as an obstacle.
Lb58f_check_robot_collision_inc_y:
    inc h  ; y += 1
    inc h
    ld a, h
    cp #fd
    jr nc, Lb5ca_collision  ; check if we are out of map bounds
    call Lb5cd_robot_map_collision_internal
    ret nz
    inc hl  ; x += 1
    call Lb5cd_robot_map_collision_internal
    ret nz
    inc h  ; y += 1
    inc h
    ld a, h
    cp #fd  ; check if we are out of map bounds
    jr nc, Lb5c8_no_collision
    ld a, (hl)
    and e
    ret nz
    dec hl  ; x -= 1
    ld a, (hl)
    and e
    ret nz
    dec hl  ; x -= 1
    ld a, (hl)
    and e
    ret


; --------------------------------
; Checks if a robot can walk up (decrementing y).
; Input:
; - hl: map pointer
; - d: 8 for bipod, 12 for tracks, and 15 for antigrav (the highest map element a robot can walk 
;      over).
; - e: mask of non-walkable elements (usually just #40 to indicate other robots are not walkable).
;      But it could be #c0 when the player is lower than the height of the robot in consideration,
;      to consider the player as an obstacle.
Lb5b1_check_robot_collision_dec_y:
    dec h
    dec h  ; y -= 1
    dec h
    dec h  ; y -= 1
    ld a, h
    cp #dd  ; check if we are out of map bounds
    jr c, Lb5ca_collision
    dec hl  ; x -= 1
    ld a, (hl)
    and e
    ret nz
    inc hl  ; x += 1
    call Lb5cd_robot_map_collision_internal
    ret nz
    inc hl  ; x += 1
    call Lb5cd_robot_map_collision_internal
    ret
Lb5c8_no_collision:
    xor a
    ret
Lb5ca_collision:
    or 1
    ret


; --------------------------------
; Check if a given position in the map is walkable by the chassis of a robot.
; This is checked by seeing if the element in the map is < "d".
; Input:
; - hl: map pointer
; - d: 8 for bipod, 12 for tracks, and 15 for antigrav (the highest map element a robot can walk 
;      over).
; - e: mask of non-walkable elements (usually just #40 to indicate other robots are not walkable).
;      But it could be #c0 when the player is lower than the height of the robot in consideration,
;      to consider the player as an obstacle.
Lb5cd_robot_map_collision_internal:
    ld a, (hl)
    and #1f
    cp d
    jr nc, Lb5ca_collision  ; map element is not walkable by the current chassis.
    ld a, (hl)
    and e  ; check for objects (robots and potentially the player)
    ret


; --------------------------------
; Get highest altitude of 2x2 map area:
; input:
; - hl: x
; - b: y
; Output:
; - a: altitude
Lb5d6_map_altitude_2x2:
    push hl
    push bc
        ld a, b
        call Lcca6_compute_map_ptr
        ex de, hl
        ld c, 0
        call Lb08a_get_map_altitude
        inc de
        call Lb08a_get_map_altitude
        dec d
        dec d
        call Lb08a_get_map_altitude
        dec de
        call Lb08a_get_map_altitude
        ld a, c
    pop bc
    pop hl
    ret


; --------------------------------
; Determines how many cycles will the robot need to take to move
; depending on the terrain it is on.
; Input:
; - iy: robot pointer
Lb5f3_determine_speed_based_on_terrain:
    push bc
    push hl
        ld a, (iy + ROBOT_STRUCT_ALTITUDE)
        ld c, 0  ; flat terrain
        or a
        jr z, Lb605_terrain_type_determined
        ld c, 3  ; rugged
        cp 4
        jr c, Lb605_terrain_type_determined
        ld c, 6  ; mountains
Lb605_terrain_type_determined:
        ld a, (iy + ROBOT_STRUCT_PIECES)
        ld d, 255
Lb60a_determine_chassis_loop:
        inc d
        rrca
        jr nc, Lb60a_determine_chassis_loop
        ld a, c
        add a, d
        ld hl, Lb61d_robot_movement_speed_table
        call Ld351_add_hl_a
        ld a, (hl)
        ld (iy + ROBOT_STRICT_CYCLES_TO_NEXT_UPDATE), a
    pop hl
    pop bc
    ret

; How many cycles does the robot take to move in the different terrains,
; depending on its chassis:
Lb61d_robot_movement_speed_table:
    ;  bipod, tracks, anti-grav
    db #06, #04, #03  ; flat terrain
    db #08, #06, #03  ; rugged
    db #09, #07, #04  ; mountains


; --------------------------------
; Looks in the 4 cardinal directions to see if in any of them there are enemy robots
; that we could fire at.
; Input:
; - iy: robot ptr.
; Output:
; - e: one-hot representation of the directions where enemy robots can be found.
Lb626_check_directions_with_enemy_robots:
    ld e, 0  ; will accumulate the directions in which there are enemy robots in line.
    ld d, 8  ; initial direction (up in a one-hot encoded representation)
Lb62a_loop_direction:
    rlc e
    ld l, (iy + ROBOT_STRUCT_MAP_PTR)
    ld h, (iy + ROBOT_STRUCT_MAP_PTR + 1)
    ld b, 8  ; distance to check in directions we are not facing
    ld a, d
    cp (iy + ROBOT_STRUCT_DIRECTION)
    jr nz, Lb666_simple_check
    ld b, 10  ; look a bit further in the direction we are facing
    bit 7, (iy + ROBOT_STRUCT_PIECES)
    jr z, Lb644
    ld b, 12  ; if robot has "electronics", it can see a bit further still.
Lb644:
    ld a, d
    and #03
    jr nz, Lb657
    ; Look along the y axis (left/right):
    ld c, b  ; store the max distance for later
    dec hl  ; check with an offset of 1 tile up
    call Lb66e_check_if_enemy_robot_in_line
    ld b, c  ; restore the max distance
    inc hl  ; check with no offset
    call Lb66e_check_if_enemy_robot_in_line
    ld b, c  ; restore the max distance
    inc hl  ; check with an offset of 1 tile down
    jr Lb666_simple_check
Lb657:
    ; Look along the x axis (up/down):
    ld c, b  ; store the max distance for later
    dec h
    dec h  ; check with an offset of 1 tile left
    call Lb66e_check_if_enemy_robot_in_line
    ld b, c  ; restore the max distance
    inc h  ; check with no offset
    inc h  ; check with an offset of 1 tile right
    call Lb66e_check_if_enemy_robot_in_line
    ld b, c  ; restore the max distance
    inc h
    inc h
Lb666_simple_check:
    ; Just check in a straight line without adjusting the offset:
    call Lb66e_check_if_enemy_robot_in_line
    rrc d  ; next direction
    jr nc, Lb62a_loop_direction
    ret


; --------------------------------
; Checks if there is an enemy robot in line with the current robot in the desired direction.
; Basically, to see if we fired a weapon in that direction, if we could hit an enemy robot.
; Input:
; - hl: map ptr.
; - b: maximum distance to check.
; - d: direction (one-hot representation).
; - e: current directions at which we found enemy robots.
; Output:
; - e: updated with whether we found an enemy robot in the current direction.
Lb66e_check_if_enemy_robot_in_line:
    push hl
        push de
            push hl
                ld hl, Lb6b0_direction_offsets - 2
                ld a, d
                ; get the position from the Lb6b0_direction_offsets array corresponding to the 
                ; one-hot bit in "d", and store it in "de"
Lb675_get_word_loop:
                inc hl
                inc hl
                rrca
                jr nc, Lb675_get_word_loop
                ld e, (hl)
                inc hl
                ld d, (hl)
            pop hl
            ; Keeps advancing in the desired direction until we get out of the map,
            ; or we find an object.
Lb67e_raycast_loop:
            add hl, de  ; add the offset to the map ptr.
            ld a, h
            sub #dd
            cp 16 * 2
            jr nc, Lb6ad_nothing_found  ; out of bounds of the map
            bit 6, (hl)
            jr nz, Lb68e_object_found  ; object found
            djnz Lb67e_raycast_loop
            jr Lb6ad_nothing_found

Lb68e_object_found:
            push iy
                call Lcdd8_get_robot_at_ptr
                ld a, (iy + ROBOT_STRUCT_CONTROL)
                ld b, (iy + ROBOT_STRUCT_STRENGTH)
            pop iy
            jr nz, Lb6ad_nothing_found
            xor (iy + ROBOT_STRUCT_CONTROL)
            jp p, Lb6ad_nothing_found  ; the robot has the same owner as the current robot.
            dec b
            jp m, Lb6ad_nothing_found  ; the robot is already destroyed
        pop de
        ld a, e
        or 1
        ld e, a  ; potential optimization: these 3 instructions are just "set 0, e".
        push de  ; push just to make sure the next pop does not mess up the stack.
Lb6ad_nothing_found:
        pop de
Lb6ae:
    pop hl
    ret

Lb6b0_direction_offsets:
    dw 1  ; right
    dw -1  ; left
    dw 512  ; down
    dw -512  ; up


; --------------------------------
; Find new bullet pointer. Friendly robots can only use bullets 1, and 2,
; and enemy robots bullets 3 and 4 (bullet 0 is reserved for player-controlled robots).
; Input:
; - ix: pointer to robot that is firing.
; Output:
; - iy: new bullet ptr
; - z: new bullet found
; - nz: no bullet slots available.
Lb6b8_find_new_bullet_ptr:
    ld iy, Ld7d3_bullets + BULLET_STRUCT_SIZE
    bit 7, (ix + ROBOT_STRUCT_CONTROL)
    jr z, Lb6c7_player_robot
    ld de, BULLET_STRUCT_SIZE * 2
    add iy, de
Lb6c7_player_robot:
    ld a, (iy + 1)
    or a
    ret z  ; first bullet is available
    ; Try next bullet:
    ld de, BULLET_STRUCT_SIZE
    add iy, de
    ld a, (iy + 1)
    or a
    ret


; --------------------------------
; Spawns a new bullet on "iy".
; Input:
; - a: weapon to fire: 1: cannon, 2: missiles, 3: phasers.
; - iy: bullet pointer to use.
; - ix: pointer to robot that fired the weapon.
Lb6d6_weapon_fire:
    ld (iy + BULLET_STRUCT_TYPE), a
    ld c, WEAPON_RANGE_DEFAULT  ; range
    cp 2  ; missiles
    jr nz, Lb6e1_not_missiles
    ld c, WEAPON_RANGE_MISSILES  ; missiles have an extended range
Lb6e1_not_missiles:
    bit 7, (ix + ROBOT_STRUCT_PIECES)
    jr z, Lb6e8_not_electronics
    inc c  ; electronics increase by one the weapon range
Lb6e8_not_electronics:
    ld (iy + BULLET_STRUCT_RANGE), c
    ld a, (ix + ROBOT_STRUCT_DIRECTION)
    ld (iy + BULLET_STRUCT_DIRECTION), a
    ld (iy + BULLET_STRUCT_ALTITUDE), 10
    ld l, (ix + ROBOT_STRUCT_X)
    ld h, (ix + ROBOT_STRUCT_X + 1)
    ld b, (ix + ROBOT_STRUCT_Y)
    call Lb724_bullet_update_internal
    ld a, (iy + 1)
    or a
    jr z, Lb70c
    ld a, 1
    ld (Lfd53_produce_in_game_sound), a  ; produce sound
Lb70c:
    ret


; --------------------------------
; Update cycle for bullets, including dealing damage to robots.
; Input:
; - iy: bullet ptr
Lb70d_bullet_update:
    ld l, (iy + BULLET_STRUCT_MAP_PTR)
    ld h, (iy + BULLET_STRUCT_MAP_PTR + 1)
    res 6, (hl)  ; remove the bullet from the map
    dec (iy + BULLET_STRUCT_RANGE)  ; decrease the lifetime of the bullet
    jp z, Lb7ea_bullet_disappear  ; if bullet has reached its maximum range, destroy it
    ld l, (iy + BULLET_STRUCT_X)
    ld h, (iy + BULLET_STRUCT_X + 1)
    ld b, (iy + BULLET_STRUCT_Y)
Lb724_bullet_update_internal:
    ; move the bullet in the direction of movement:
    ld a, (iy + BULLET_STRUCT_DIRECTION)
    rrca
    jr nc, Lb72e_not_right
    inc hl  ; x += 2
    inc hl
    jr Lb747_movement_complete
Lb72e_not_right:
    rrca
    jr nc, Lb735_not_left
    dec hl  ; x -= 2
    dec hl
    jr Lb747_movement_complete
Lb735_not_left:
    rrca
    jr nc, Lb73c_not_down
    inc b  ; y += 2
    inc b
    jr Lb741_check_out_of_map_in_y
Lb73c_not_down:
    rrca
    jr nc, Lb747_movement_complete
    dec b  ; y -= 2
    dec b
Lb741_check_out_of_map_in_y:
    ; Notice that we only need to check out of bounds in the y axis, as, in the x axis, there's
    ; always obstacles at the ends of the map, so, we don't need to check.
    ld a, b
    cp MAP_WIDTH
    jp nc, Lb7ea_bullet_disappear  ; if y > 16 or < 0, make it disappear.
Lb747_movement_complete:
    ld (iy + BULLET_STRUCT_X), l
    ld (iy + BULLET_STRUCT_X + 1), h
    ld (iy + BULLET_STRUCT_Y), b
    ; Check if the bullet collided with the map:
    call Lb5d6_map_altitude_2x2
    cp (iy + BULLET_STRUCT_ALTITUDE)
    jp nc, Lb7ea_bullet_disappear  ; collision
    ld a, b
    ; Calculate the new map pointer given the new position:
    call Lcca6_compute_map_ptr
    ld (iy + BULLET_STRUCT_MAP_PTR), l
    ld (iy + BULLET_STRUCT_MAP_PTR + 1), h
    push hl
        dec hl  ; x -= 1
        dec h  ; y -= 1
        dec h
        ld a, h
        cp #dd  ; check if the pointer is out of the map area
        jr c, Lb77c_continue  ; out of bounds in that direction, so, we can skip a few collision 
                              ; checks.
        bit 6, (hl)
        jr nz, Lb7a7_potentially_hit_a_robot
        inc hl  ; x += 1
        bit 6, (hl)
        jr nz, Lb7a7_potentially_hit_a_robot
        inc hl  ; x += 1
        bit 6, (hl)
        jr nz, Lb7a7_potentially_hit_a_robot
        dec hl  ; restore the x coordinate
        dec hl
Lb77c_continue:
        inc h  ; y += 1
        inc h
        bit 6, (hl)
        jr nz, Lb7a7_potentially_hit_a_robot
        inc hl  ; x += 1
        bit 6, (hl)
        jr nz, Lb7a7_potentially_hit_a_robot
        inc hl  ; x += 1
        bit 6, (hl)
        jr nz, Lb7a7_potentially_hit_a_robot
        dec hl  ; x -= 2
        dec hl
        inc h  ; y += 1
        inc h
        ld a, h
        cp #fd  ; check if the pointer is out of the map area
        jr nc, Lb7a3_no_robot_collision
        bit 6, (hl)
        jr nz, Lb7a7_potentially_hit_a_robot
        inc hl
        bit 6, (hl)
        jr nz, Lb7a7_potentially_hit_a_robot
        inc hl
        bit 6, (hl)
        jr nz, Lb7a7_potentially_hit_a_robot
Lb7a3_no_robot_collision:
    pop hl
    set 6, (hl)  ; we mark the bullet in the map again
    ret
Lb7a7_potentially_hit_a_robot:
        push iy
            ld e, (iy + BULLET_STRUCT_TYPE)
            ld c, 252  ; c determines the SFX that will be played with this event
            call Lcdd8_get_robot_at_ptr
            jr nz, Lb7de_collision_handled
            ld a, (iy + ROBOT_STRUCT_STRENGTH)
            dec a
            jp m, Lb7de_collision_handled  ; robot was already destroyed
            ; Determine the damage dealt:
            ld a, 60
            sub (iy + ROBOT_STRUCT_HEIGHT)
            sub (iy + ROBOT_STRUCT_ALTITUDE)
            srl a
            srl a
            ld d, a  ; d = "base damage" = (60 - (robot height + altitude)) / 4
            ld b, e  ; bullet type (1: cannon, 2: missiles, 3: phaser)
Lb7c8_damage_calculation_loop:
            add a, d
            djnz Lb7c8_damage_calculation_loop
            ; Here a = 2x base damage for cannon, 3x for missiles, and 4x for phasers.
            ld b, a
            ld c, 250  ; sfx
            ld a, (iy + ROBOT_STRUCT_STRENGTH)
            sub b  ; deal damage
            jr z, Lb7d7_robot_destroyed
            jp p, Lb7db_robot_hit
Lb7d7_robot_destroyed:
            ld a, -4  ; mark negative strength, which will make the robot blink before being 
                      ; destroyed.
            ld c, 200  ; sfx
Lb7db_robot_hit:
            ld (iy + ROBOT_STRUCT_STRENGTH), a  ; update robot health
Lb7de_collision_handled:
        pop iy
    pop hl
    ld (iy + BULLET_STRUCT_MAP_PTR + 1), 0  ; make the bullet disappear
    ld a, c
    ld (Lfd53_produce_in_game_sound), a  ; produce sound
    ret


; --------------------------------
; Make a bullet disappear.
; Input:
; - iy: bullet pointer.
Lb7ea_bullet_disappear:
    ld (iy + 1), 0
    ld a, -4
    ld (Lfd53_produce_in_game_sound), a  ; produce sound
    ret


; --------------------------------
; Enemy AI update cycle. It works as follows:
; - with probability 0.25 it does nothing.
; - it then tries to pick a robot at random (from the set of 24 possible robots).
; - if it's an active robot, it will control it via "Lb920_enemy_ai_single_robot_control"
; - otherwise, it picks a random warbase
; - if it belongs to the enemy, it will try to produce a random robot with come constraints.
; - if any of the constraints is violated, then the enemy AI will just do nothing.
; - otherwise, it will construct the robot with "stop & defend" orders, and wait for it 
;   to be randomly picked up later to be assigned new orders.
Lb7f4_update_enemy_ai:
    call Ld358_random
    and #1f
    cp MAX_ROBOTS_PER_PLAYER
    ret nc  ; with 0.25 probability the enemy AI does nothing.
    ; Use the generated random number to get the pointer of a robot at random:
    add a, a
    add a, a
    add a, a
    ld l, a
    ld h, 0
    add hl, hl
    ld de, Ldb80_player2_robots
    add hl, de
    push hl
    pop iy  ; iy now has the pointer to a random robot from the enemy AI.
    ld a, 1
    ld (Lfd51_current_robot_player_or_enemy), a
    ; Check if the pointer corresponds to an active robot:
    ld a, (iy + ROBOT_STRUCT_MAP_PTR + 1)
    or a
    jp nz, Lb920_enemy_ai_single_robot_control

    ; pick a random warbase otherwise:
    ld b, N_WARBASES
    ld hl, Lfd70_warbases + BUILDING_STRUCT_TYPE
Lb81b_pick_random_warbase_loop:
    call Ld358_random
    and 1
    jr z, Lb827_next_warbase
    ld a, (hl)
    cp #20
    jr z, Lb0ca_enemy_ai_control_warbase  ; also ensures it's a warbase
Lb827_next_warbase:
    ld a, BUILDING_STRUCT_SIZE
    call Ld351_add_hl_a
    djnz Lb81b_pick_random_warbase_loop
    ; no warbase selected
    ret

Lb0ca_enemy_ai_control_warbase:
    ; Notice that if we reached here, "iy" has the pointer to an empty
    ; robot position.
    dec hl
    ld b, (hl)
    dec hl
    ld a, (hl)
    dec hl
    ld l, (hl)
    ld h, a  ; hl = x coordinate, b = y coordinate
    ld a, b
    push hl
        exx
    pop hl
    ld b, a  ; hl = x coordinate, b = y coordinate in both ghost and regular registers
             ; this is to set the robot coordinates below.
    exx
    call Lcca6_compute_map_ptr
    ; Check if the entrance to the warbase is blocked:
    push hl
        ld a, (hl)
        inc h
        inc h
        or (hl)
        dec hl
        or (hl)
        inc hl
        inc hl
        or (hl)
        and #40
    pop hl
    ret nz  ; if there is something blocking the entrance of the warbase, exit.
    call Ld358_random  ; Note: not sure why calling random twice.
    call Ld358_random
    ld c, a  ; save the random number for later
    ld (iy + ROBOT_STRUCT_PIECES), a
    and 7
    cp 1  ; bipod
    jr z, Lb864_correct_chasis
    cp 2  ; tracks
    jr z, Lb864_correct_chasis
    cp 4  ; antigrav
    ret nz  ; if we picked more than one chassis, just return.
Lb864_correct_chasis:
    ld a, c  ; restore the random number
    rrca
    rrca
    rrca
    and #0f
    ret z  ; if we picked no weapon, just return.
    cp #f
    ret z  ; if we picked too many weapons (only 3 allowed), just return.
    ld c, a  ; save the weapon selection
    ld a, (Lfd49_player2_robot_count)
    rrca
    rrca
    rrca
    inc a
    and 3
    ld b, a  ; enemy # of robots / 8 + 1
    call Lb505_count_number_of_active_bits_in_the_lower_nibble
    cp b
    ret c  ; the first 8 robots, can at most have 1 weapon, the next 8 can have two, etc.

    ; Check if player 2 has enough resources:
    ld hl, Lfd4a_player2_resource_counts
    ld de, Lfd29_resource_counts_buffer
    ld bc, 7
    ldir
    ld c, (iy + ROBOT_STRUCT_PIECES)
    ld d, 0  ; how many "general resources" will we need to use.
    ld b, 8
Lb890_check_resource_availability_loop:
    rrc c
    jr nc, Lb8b8_next_piece
    ld a, 8
    sub b
    push af
        ld hl, Lcaf0_piece_costs
        call Ld351_add_hl_a
        ld e, (hl)  ; cost of the piece
    pop af
    ld hl, Lcaf8_piece_factory_type
    call Ld351_add_hl_a
    ld a, (hl)  ; type of factory that can produce this piece
    ld hl, Lfd29_resource_counts_buffer
    call Ld351_add_hl_a
    ld a, (hl)
    sub e
    jp p, Lb8b7_no_need_for_general_resources
    neg
    add a, d  ; add the left over to the general resources cost
    ld d, a
    xor a  ; zero out the resources we have left for this factory type.
Lb8b7_no_need_for_general_resources:
    ld (hl), a
Lb8b8_next_piece:
    djnz Lb890_check_resource_availability_loop
    ; Check that we have enough general resources:
    ld hl, Lfd29_resource_counts_buffer
    ld a, (hl)
    srl a
    cp 11
    jr nc, Lb8c6_more_than_22_resources_left
    ld a, 11
Lb8c6_more_than_22_resources_left:
    cp d
    ret c  ; The maximum general resources we can spend on a robot is half of the amount we have (
           ; except if we need to spend less or equal to 11).

    ld a, (hl)
    sub d
    ret m  ; we do not have enough resources to build the robot, return.

    ; subtract the costs from the actual player 2 resources:
    ld (hl), a
    ld de, Lfd4a_player2_resource_counts
    ld bc, 7
    ldir

    ; Start the robot!
    ld (iy + ROBOT_STRUCT_CONTROL), ROBOT_CONTROL_ENEMY_AI  ; mark the owner
    exx
        call Lcc7c_set_robot_position  ; set position
    exx
    ld (iy + ROBOT_STRUCT_DESIRED_MOVE_DIRECTION), 4  ; by default move down (to exit the warbase)
    ld (iy + ROBOT_STRUCT_DIRECTION), 4
    ld (iy + ROBOT_STRUCT_NUMBER_OF_STEPS_TO_KEEP_WALKING), 3
    ld (iy + ROBOT_STRUCT_ALTITUDE), 0
    ld (iy + ROBOT_STRUCT_ORDERS), ROBOT_ORDERS_STOP_AND_DEFEND
    ld (iy + ROBOT_STRICT_CYCLES_TO_NEXT_UPDATE), 1
    ld (iy + ROBOT_STRUCT_STRENGTH), 100
    ld (iy + ROBOT_STRUCT_ORDERS_ARGUMENT), 255
    ; calculate robot height (when a player constructs it, this is calculated in the robot editing 
    ; UI):
    ld c, (iy + ROBOT_STRUCT_PIECES)
    ld b, 8
    ld d, 0
Lb904_robot_height_loop:
    rrc c
    jr nc, Lb914_next_piece
    ld a, 8
    sub b
    ld hl, Ld7b4_piece_heights
    call Ld351_add_hl_a
    ld a, (hl)
    add a, d
    ld d, a
Lb914_next_piece:
    djnz Lb904_robot_height_loop
    ld (iy + ROBOT_STRUCT_HEIGHT), d
    call Lbb40_count_robots
    call Ld293_update_stats_in_right_hud
    ret


; --------------------------------
; If the robot already has orders (!= from "stop & defend"):
; - with a 1 / 32 chance they will be kept.
; - if the robot target is of the type it was looking for, a new order will be given (note: I think 
;   this is a bug, look my other note below).
; - if the robot has not reached the target, a new order will be given.
; If new orders are to be given:
; - if robot has nuclear, it will try to randomly go and destroy player factories/warbases.
; - otherwise, capture neutral/player factories or player warbases.
; - if it cannot find a target, then destroy player robots.
; Input:
; - iy: robot ptr.
Lb920_enemy_ai_single_robot_control:
    ld a, (iy + ROBOT_STRUCT_ORDERS)
    or a
    jr z, Lb95d_assign_new_orders  ; if current orders are stop & defend

    ; The robot already had orders different from stop & defend.
    ld b, a
    call Ld358_random
    and #1f
    ret nz  ; 1 / 32 chance to keep the same orders the robot still has.
    ld a, b
    cp ROBOT_ORDERS_DESTROY_ENEMY_FACTORIES
    jr c, Lb95d_assign_new_orders  ; if orders where stop & defend, advance, retreat or destroy 
                                   ; robots, assign new orders.

    ; Otherwise, look for a target:
    ld a, (iy + ROBOT_STRUCT_ORDERS)
    call Lb3d5_prepare_robot_order_building_target_search
    ld a, (iy + ROBOT_STRUCT_ORDERS_ARGUMENT)
    ld b, a
    add a, a
    add a, a
    add a, b
    call Ld351_add_hl_a  ; hl now contains a pointer to the target building type flag
    ld a, (hl)
    and #e0
    cp e  ; compare if the target flags are the same as we are looking for.
    jr z, Lb95d_assign_new_orders  ; if the robot's target was a correct one, assign new orders (
                                   ; note: this is strange, I think this is a bug, and it was meant 
                                   ; to be "nz").
    ; Now check, if the robot has arrived to the target, keep orders, otherwise, change.
    dec hl
    ld a, (iy + ROBOT_STRUCT_Y)
    sub (hl)
    jr nz, Lb95d_assign_new_orders  ; if the target is not in the same "y" coordinate, assign new 
                                    ; orders.
    dec hl
    ld d, (hl)
    dec hl
    ld e, (hl)
    ld l, (iy + ROBOT_STRUCT_X)
    ld h, (iy + ROBOT_STRUCT_X + 1)
    xor a
    sbc hl, de
    ret z  ; if the robot is in the same "x" coordinate as the target, keep the orders!

Lb95d_assign_new_orders:
    ; Randomly assigns a robot to destroy/capture factories or warbases. 
    ; - destroy if the robot has nuclear, and capture if it does not.
    ; - in case it cannot find a target for the random orders it was assigned, it will just 
    ;   be tasked to destroy player robots.
    ld (iy + ROBOT_STRUCT_ORDERS), ROBOT_ORDERS_DESTROY_ENEMY_ROBOTS  ; Potential optimization: 
                                                                      ; this assignment will always 
                                                                      ; be overwritten. So, it can 
                                                                      ; be eliminated.
    bit 6, (iy + ROBOT_STRUCT_PIECES)
    jr z, Lb976_robot_does_not_have_nuclear
    ; robot has nuclear:
    ; randomly assign it to destroy either player factories or player warbases:
    call Ld358_random
    ld b, a
    rlca
    or b
    and 1
    add a, ROBOT_ORDERS_DESTROY_ENEMY_FACTORIES
    ld (iy + ROBOT_STRUCT_ORDERS), a
    jr Lb989_new_orders_assigned

Lb976_robot_does_not_have_nuclear:
    ; Randomly assign it to capture: neutral factories, enemy factories or enemy warbases:
    ld c, ROBOT_ORDERS_STOP_AND_DEFEND
    call Ld358_random
    rrca
    jr c, Lb983
    inc c
    rrca
    jr c, Lb983
    inc c
Lb983:
    ld a, c
    add a, ROBOT_ORDERS_CAPTURE_NEUTRAL_FACTORIES
    ld (iy + ROBOT_STRUCT_ORDERS), a

Lb989_new_orders_assigned:
    ld l, (iy + ROBOT_STRUCT_X)
    ld h, (iy + ROBOT_STRUCT_X + 1)
    ld (iy + ROBOT_STRUCT_ORDERS_ARGUMENT), 255
    call Lb34d_find_capture_or_destroy_target
    ld (iy + ROBOT_STRUCT_ORDERS_ARGUMENT), d
    ret nz  ; if target found, we are done.
    ; Otherwise, just try to destroy enemy robots
    ld (iy + ROBOT_STRUCT_ORDERS), ROBOT_ORDERS_DESTROY_ENEMY_ROBOTS
    ret


; --------------------------------
; Nuclear bomb effect: destroys buildings and robots nearby and replace with debris.
; Input:
; - iy: robot pointer.
Lb99f_fire_nuclear_bomb:
    ld hl, Lfd70_warbases + BUILDING_STRUCT_TYPE
    ld c, 0  ; building index
    ld de, #070a  ; nuclear bomb effect radius for warbases (something in between a circle and a 
                  ; square):
                  ; - maximum distance in each axis of 7
                  ; - maximum sum of distances in each axis of 10
Lb9a7_building_loop:
    push hl
        bit 7, (hl)  ; check if the building is already destroyed.
        jr nz, Lb9dd_skip_building
        dec hl
        ld a, c
        cp N_WARBASES
        ; Calculate the distance in the y axis between robot and building.
        ld a, (iy + ROBOT_STRUCT_Y)
        jr nc, Lb9b7_not_a_warbase
        add a, 4
Lb9b7_not_a_warbase:
        inc a
        sub (hl)
        ; "a" now has the difference in the y axis, now calculate the absolute value:
        jp p, Lb9be_positive_difference
        neg
Lb9be_positive_difference:
        ld b, a  ; store the difference in y.
        cp d
        jr nc, Lb9dd_skip_building  ; building is too far
        ; calculate the distance in the x axis:
        push de
            dec hl
            ld d, (hl)
            dec hl
            ld e, (hl)  ; building x
            ld l, (iy + ROBOT_STRUCT_X)
            ld h, (iy + ROBOT_STRUCT_X + 1)  ; robot x
            call Lb3ca_distance_from_hl_to_de
        pop de
        ld a, h
        or a
        jr nz, Lb9dd_skip_building  ; too far
        ld a, l
        cp d
        jr nc, Lb9dd_skip_building  ; too far
        add a, b
        cp e  ; check if the sum of distances is larger than 10
        jr c, Lb9f2_building_in_range_of_nuclear_bomb
Lb9dd_skip_building:
    pop hl
    ; next building
    ld a, BUILDING_STRUCT_SIZE
    call Ld351_add_hl_a
    inc c
    ld a, c
    cp 4
    jr c, Lb9a7_building_loop
    ld de, #0507  ; nuclear bomb effect radius for factories (something in between a circle and a 
                  ; square):
                  ; - maximum distance in each axis of 5
                  ; - maximum sum of distances in each axis of 7
    cp N_WARBASES + N_FACTORIES
    jr c, Lb9a7_building_loop
    jr Lba02_look_for_robots_in_range_of_nuclear_bomb

Lb9f2_building_in_range_of_nuclear_bomb:
    ; A nuclear bomb will only destroy at most one building. As soon as
    ; a building to destroy is found, we are done with the above loop:
    pop hl
    ld a, c
    cp N_WARBASES
    jr nc, Lb9fd_factory
    call Lbbf9_destroy_warbase
    jr Lba02_look_for_robots_in_range_of_nuclear_bomb
Lb9fd_factory:
    sub N_WARBASES
    call Lbbd8_destroy_factory

Lba02_look_for_robots_in_range_of_nuclear_bomb:
    ; Look for robots nearby to destroy
    ld l, (iy + ROBOT_STRUCT_MAP_PTR)
    ld h, (iy + ROBOT_STRUCT_MAP_PTR + 1)
    push iy
        ld de, -(4*MAP_LENGTH + 4)
        add hl, de  ; subtract (4, 4) to the robot map pointer.
        ; look for robots in a 9x9 window around the robot
        ld bc, #0909
Lba11_loop_y:
        push bc
            push hl
                ld a, h
                cp #df
                jr c, Lba61_next_y  ; out of map bounds
                cp #fd
                jr nc, Lba61_next_y  ; out of map bounds
                ld a, c
                cp 1
                jr z, Lba2d_double_x_increment
                cp 2
                jr z, Lba30_x_increment
                cp 8
                jr z, Lba30_x_increment
                cp 9
                jr nz, Lba33_loop_x
Lba2d_double_x_increment:
                inc hl
                dec b
                dec b
Lba30_x_increment:
                inc hl
                dec b
                dec b
Lba33_loop_x:
                push bc
                    ld a, (hl)
                    bit 6, a
                    jr z, Lba44_robots_handled
                    call Lcdd8_get_robot_at_ptr
                    jr nz, Lba44_robots_handled
                    ld (iy + ROBOT_STRUCT_MAP_PTR + 1), 0  ; mark robot as destroyed
                    res 6, (hl)  ; remove from map
Lba44_robots_handled:
                    ; Destroy map elements
                    ld a, (hl)
                    bit 5, a
                    jr nz, Lba5d_next_x
                    and #1f
                    cp 17  ; do not destroy terrain
                    jr c, Lba5d_next_x
                    cp 21
                    jr nc, Lba5d_next_x  ; do not destroy the fences that mark the end of the map 
                                         ; in each end.
                    call Ld358_random
                    and 1
                    add a, 6  ; pick a random piece of debris
                    call Lbd91_add_element_to_map
Lba5d_next_x:
                pop bc
                inc hl
                djnz Lba33_loop_x
Lba61_next_y:
            pop hl
            inc h  ; y+= 1
            inc h
        pop bc
        dec c
        jr nz, Lba11_loop_y
          ; mark the player in the map and redraw
        call Lcca0_compute_player_map_ptr
        set 7, (hl)
        call Lccbd_redraw_game_area
    pop iy
    ld (iy + ROBOT_STRUCT_MAP_PTR + 1), 0  ; destroy the robot that triggered the nuclear bomb
    call Lba87_nuclear_bomb_visual_effect
    ld a, 1
    ld (Lfd52_update_radar_buffer_signal), a
    call Lbb40_count_robots
    call Lbb09_update_players_warbase_and_factory_counts
    jp Ld293_update_stats_in_right_hud


; --------------------------------
; Nuclear bomb visual and sound effect. 
; Basically pick random "paper" colors for the game area and keep
; changing them, while producing noise in the background.
Lba87_nuclear_bomb_visual_effect:
    ; Store the original screen attributes to the L5b00 buffer.
    ld de, L5b00
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #0021  ; beginning of the game-play area.
    ld bc, #1414  ; 20, 20
Lba90_loop_y:
    push bc
Lba91_loop_x:
        ldi
        inc c
        djnz Lba91_loop_x
        ld a, 12
        call Ld351_add_hl_a
    pop bc
    dec c
    jr nz, Lba90_loop_y

    ; Visual and sound effect
    ld bc, #f401
Lbaa2_nuclear_bomb_visual_effect_loop:
    call Lbaee_nuclear_explosion_sfx
    push bc
        ld hl, L5800_VIDEOMEM_ATTRIBUTES + #0021  ; beginning of the game-play area.
        ld bc, #1414  ; 20, 20
Lbaac_random_color_loop:
        call Ld358_random
        and #38  ; random number of the form 8 * [0 - 7]  ; random attribute with black ink,
                 ; basically.
        cp #10
        jr c, Lbaac_random_color_loop  ; do not allow black on black or black on blue.
        cp e
        jr z, Lbaac_random_color_loop  ; do not allow the same color as before.
        ld e, a
        ; add the new random paper color to all the game area:
Lbab9_loop_y:
        push bc
Lbaba_loop_x:
            ld a, (hl)
            and #38
            jr z, Lbac4_skip  ; do not change the black on black areas (sky).
            ld a, (hl)
            and #c7  ; leave ink / brightness the same.
            or e  ; add the new paper color.
            ld (hl), a
Lbac4_skip:
            inc hl
            djnz Lbaba_loop_x
            ld a, 12
            call Ld351_add_hl_a
        pop bc
        dec c
        jr nz, Lbab9_loop_y
    pop bc
    djnz Lbaa2_nuclear_bomb_visual_effect_loop

    ; Restore the original screen attributes from the L5b00 buffer.
    ld hl, L5b00
    ld de, L5800_VIDEOMEM_ATTRIBUTES + #0021
    ld bc, #1414  ; 20, 20
Lbadc_loop_y:
    push bc
Lbadd_loop_x:
        ldi
        inc c
        djnz Lbadd_loop_x
        ld a, 12
        add a, e
        ld e, a
        jr nc, Lbae9_continue
        inc d
Lbae9_continue:
    pop bc
    dec c
    jr nz, Lbadc_loop_y
    ret


; --------------------------------
; Produces part of the sfx of the nuclear explosion.
; This function is called many times in a loop (above), and the
; combination of all calls, produces the nuclear explosion sound
; effect.
; Input:
; - c: wave period.
; - b: number of bytes to read to generate noise.
Lbaee_nuclear_explosion_sfx:
    push bc
        ld hl, 144
Lbaf2_outer_loop:
        push bc
            ; read a value from some position in the ZX Spectrum BIOS (used to
            ; get some semi-random values to produce noise):
            ld a, (hl)
            and 16
            out (ULA_PORT), a  ; change MIC/EAR state (to produce sound).
            inc hl
            ; insert some delay before we change the wave again:
Lbaf9_inner_loop:
            dec c
            nop
            nop
            jr nz, Lbaf9_inner_loop
        pop bc
        djnz Lbaf2_outer_loop
    pop bc
    dec b
    dec b
    dec b
    inc c
    inc c
    inc c
    ret


; --------------------------------
; Clears the factory/warbase counters, and recomputes it from scratch.
Lbb09_update_players_warbase_and_factory_counts:
    ; clear warbase/factory counts:
    ld hl, Lfd3a_player1_base_factory_counts
    ld b, 7
Lbb0e_clear_player1_loop:
    ld (hl), 0
    inc hl
    djnz Lbb0e_clear_player1_loop
    inc hl  ; skip robot count
    ld b, 7
Lbb16_clear_player2_loop:
    ld (hl), 0
    inc hl
    djnz Lbb16_clear_player2_loop
    ld de, Lfd70_warbases + BUILDING_STRUCT_TYPE
    ld b, N_WARBASES + N_FACTORIES
Lbb20:
    ld a, (de)
    or a
    jp m, Lbb39_skip
    ld hl, Lfd3a_player1_base_factory_counts
    bit 6, a  ; bit 6 indicates it belongs to player 1
    jr nz, Lbb33_increment_counter
    ld hl, Lfd42_player2_base_factory_counts
    bit 5, a  ; bit 5 indicates it belongs to player 2 (AI)
    jr z, Lbb39_skip
Lbb33_increment_counter:
    and 7  ; ignore the owners, and just keep the type
    call Ld351_add_hl_a
    inc (hl)  ; increment the count
Lbb39_skip:
    ld a, e
    add a, 5
    ld e, a
    djnz Lbb20
    ret


; --------------------------------
; Counts the number of robots of each player and stores it in "Lfd41_player1_robot_count" and 
; "Lfd49_player2_robot_count"
Lbb40_count_robots:
    ld hl, Lda00_player1_robots+1
    call Lbb50_count_player_robots
    ld (Lfd41_player1_robot_count), a
    call Lbb50_count_player_robots
    ld (Lfd49_player2_robot_count), a
    ret


; --------------------------------
; Counts the number of robots a player has
; Input:
; - hl: pointer to the table of robots of a given player (offset by one byte)
; Returns:
; - a: # robots
Lbb50_count_player_robots:
    ld b, MAX_ROBOTS_PER_PLAYER
    ld c, 0
    ld de, 16
Lbb57_count_player_robots_loop:
    ld a, (hl)
    or a
    jr z, Lbb5c_no_robot
    inc c
Lbb5c_no_robot:
    add hl, de
    djnz Lbb57_count_player_robots_loop
    ld a, c
    ret


; --------------------------------
; Gets factory # "a", removes any records of being owned by a previous player, and assigns it to 
; player "b".
; Input:
; - a: factory index
; - b: owner
Lbb61_assign_factory_to_player:
    ld hl, Lfd84_factories + BUILDING_STRUCT_TYPE
    call Lbbb9_mark_ath_building_and_get_ptr
    dec h
    dec h
    dec h
    dec h
    inc hl
    inc hl
    call Lbc5d_remove_decoration  ; remove a potential enemy flag
    dec hl
    dec hl
    dec hl
    dec hl
    call Lbc5d_remove_decoration  ; remove a potential player flag
    ld a, b  ; owner
    or a
    jr z, Lbb7f_assign_to_player
    ; the enemy sets the flag in a different position than the player
    inc hl
    inc hl
    inc hl
    inc hl
Lbb7f_assign_to_player:
    add a, 7  ; add a flag
    ld c, a
    call Lbc43_add_decoration_to_map  ; Potential optimization: tail recursion.
    ret


; --------------------------------
; Input:
; - a: warbase index
; - b: player to assign it to
Lbb86_assign_warbase_to_player:
    ld hl, Lfd70_warbases + BUILDING_STRUCT_TYPE
    call Lbbb9_mark_ath_building_and_get_ptr
    ld a, h
    sub 8
    ld h, a
    call Lbc5d_remove_decoration
    dec l
    dec l
    dec l
    dec l
    call Lbc5d_remove_decoration
    ld a, l
    add a, 8
    ld l, a
    call Lbc5d_remove_decoration
    ld c, 8
    ld a, b
    or a
    jp nz, Lbc43_add_decoration_to_map
    dec l
    dec l
    dec l
    dec l
    ld c, a
    call Lbc43_add_decoration_to_map
    dec l
    dec l
    dec l
    dec l
    ld c, 7
    jp Lbc43_add_decoration_to_map


; --------------------------------
; Marks whether the a-th warbase/factory belongs to player 1 or 2, and returns
; its pointer in the map.
; Input:
; - a: index of warbase/factory
; - hl: ptr to the beginning of the warbase/factory + 3
; - b: owner
Lbbb9_mark_ath_building_and_get_ptr:
    ld c, a
    add a, a
    add a, a
    add a, c
    call Ld351_add_hl_a  ; hl = hl + a * 5
    ld a, b
    or a
    ld a, #40  ; if player == 0, mark bit 6
    jr z, Lbbc7_neutral
    rrca  ; if player != 0, mark bit 5 instead
Lbbc7_neutral:
    ld c, a
    ld a, (hl)
    and 31
    or c
    ld (hl), a  ; update the location in the map with the neutral/occupied mark
Lbbcd_get_map_ptr_of_warbase:
    dec hl
    ld c, (hl)
    dec hl
    ld a, (hl)
    dec hl
    ld l, (hl)
    ld h, a
    ld a, c
    jp Lcca6_compute_map_ptr


; --------------------------------
; Destroy a factory and replace it with debris.
; Input:
; - a: factory index.
Lbbd8_destroy_factory:
    ld hl, Lfd84_factories + BUILDING_STRUCT_TYPE
    call Lbc1c_mark_building_as_destroyed_and_get_map_ptr
    push hl
        ; Remove the potential flags (player/enemy) and the factory type decoration:
        dec h
        dec h
        dec h
        dec h
        inc hl
        inc hl
        call Lbc5d_remove_decoration
        dec hl
        dec hl
        call Lbc5d_remove_decoration
        dec hl
        dec hl
        call Lbc5d_remove_decoration
    pop hl
    ld de, Lbfe2_factory
    jp Lbc27_replace_building_by_debris


; --------------------------------
; Destroy a warbase and replace it with debris.
; Input:
; - a: warbase index.
Lbbf9_destroy_warbase:
    ld hl, Lfd70_warbases + BUILDING_STRUCT_TYPE
    call Lbc1c_mark_building_as_destroyed_and_get_map_ptr
    push hl
        ; Remove the potential flags (player/enemy) and the warbase "H" decoration:
        ld a, h
        sub 8
        ld h, a
        call Lbc5d_remove_decoration
        dec l
        dec l
        dec l
        dec l
        call Lbc5d_remove_decoration
        ld a, l
        add a, 8
        ld l, a
        call Lbc5d_remove_decoration
    pop hl
    ld de, Lbfb2_warbase
    jp Lbc27_replace_building_by_debris


; --------------------------------
; Marks a given warbase as destroyed, and returns the map pointer where it is located.
; Input:
; - hl: warbases array ptr + 3
; - a: warbase index
Lbc1c_mark_building_as_destroyed_and_get_map_ptr:
    ld c, a
    add a, a
    add a, a
    add a, c  ; a *= BUILDING_STRING_SIZE
    call Ld351_add_hl_a
    ld (hl), #80  ; mark warbase as destroyed
    jr Lbbcd_get_map_ptr_of_warbase


; --------------------------------
; Replace a building by debris. This is used when factories/warbases are destroyed.
; Input:
; - hl: map pointer of the building.
; - de: pointer to a building definition.
Lbc27_replace_building_by_debris:
    ld a, (de)
    or a
    jr z, Lbc35
    call Ld358_random  ; select a random debris graphic
    and 1
    add a, 6
    call Lbd91_add_element_to_map
Lbc35:
    ; See if the building has more parts. Each part is a 3 byte block: type, x offset, y offset. If 
    ; the offsets are both 0, it means there are no more parts.
    inc de
    ld a, (de)
    ld c, a
    inc de
    ld a, (de)
    ld b, a
    inc de
    or c
    ret z  ; The offsets are zero, there are no more parts.
    call Lbd7f_add_map_ptr_offset
    jr Lbc27_replace_building_by_debris


; --------------------------------
; Finds an empty spot in the building decoration list, and adds a decoration
; record pointing at position "hl" in the map.
; Input:
; - hl: map ptr
; - c: type
Lbc43_add_decoration_to_map:
    ld de, Lff01_building_decorations + 1
    ld b, (N_WARBASES + N_FACTORIES) * 2
Lbc48_loop:
    ld a, (de)
    or a
    jr z, Lbc52_empty_spot_found
    inc de
    inc de
    inc de
    djnz Lbc48_loop
    ret
Lbc52_empty_spot_found:
    dec de
    set 6, (hl)  ; mark bit 6 of the map position
    ex de, hl
        ld (hl), e  ; map pointer
        inc hl
        ld (hl), d  ; map pointer
        inc hl
        ld (hl), c  ; type
    ex de, hl
    ret


; --------------------------------
; Searches for a building owner record with ptr == hl, and removes it.
; Input:
; - hl: map ptr
Lbc5d_remove_decoration:
    push iy
    push bc
        call Lcdf5_find_building_decoration_with_ptr
        jr nz, Lbc6b_not_found
        ld (iy + 1), 0  ; removes the record
        res 6, (hl)  ; removes the mark from the map
Lbc6b_not_found:
    pop bc
    pop iy
    ret


; --------------------------------
; Initializes the map buffer in Ldd00_map and all the warbase/factory/flag records.
Lbc6f_initialize_map:
    ; Clear the map:
    ld hl, Ldd00_map
    ld d, h
    ld e, l
    inc de
    ld bc, MAP_LENGTH * MAP_WIDTH - 1
    ld (hl), 0
    ldir

    ; Clear the minimap:
    ld hl, Ld800_radar_view1
    ld d, h
    ld e, l
    inc de
    ld bc, 255
    ld (hl), 0
    ldir

    ld hl, Lbda9_map_elements_part1
    ld d, 0  ; indicates x < 256
    call Lbcd6_add_elements_to_map  ; Write map elements to the map buffer (those with x < 256)

    ld hl, Lbe79_map_elements_part2
    ld d, 1  ; indicates x >= 256
    call Lbcd6_add_elements_to_map  ; Write map elements to the map buffer (those with x >= 256)

    ld iy, Lfd84_factories
    ld ix, Lfd70_warbases

    ld hl, Lbf46_warbases_factories_part1
    ld d, 0
    call Lbcf9_add_warbases_and_factories_to_map

    ld hl, Lbf6e_warbases_factories_part2
    ld d, 1
    call Lbcf9_add_warbases_and_factories_to_map

    xor a
    ld b, a
    call Lbb86_assign_warbase_to_player  ; warbase 0 to player 1
    ld a, 1
    ld b, a
    call Lbb86_assign_warbase_to_player  ; warbase 1 to player 2
    ld a, 2
    ld b, 1
    call Lbb86_assign_warbase_to_player  ; warbase 2 to player 2
    ld a, 3
    ld b, 1
    call Lbb86_assign_warbase_to_player  ; warbase 3 to player 2
    call Lbb09_update_players_warbase_and_factory_counts  ; compute the warbase/factory counts
    ld a, 1
    ld (Lfd52_update_radar_buffer_signal), a
    call Lb024_add_player_to_map_and_update_radar  ; Potential optimization: tail recursion.
    ret


; --------------------------------
; Adds a list of map elements to the map buffer.
; Input:
; - d: A 0 or a 1. Indicates whether x coordinates start at 0 or at 256.
Lbcd6_add_elements_to_map:
Lbcd6_loop:
    ld a, (hl)
    or a
    ret z  ; a 0 at the end indicates end of data.
    ld c, a  ; element type
    inc hl
    ld e, (hl)  ; x
    inc hl
    ld a, (hl)  ; y % 256
    inc hl  ; we have read 3 bytes from the data in: c, e, a.
    push hl
    push de
        ld hl, Ldd00_map
        add a, a
        add a, h
        ld h, a
        add hl, de  ; hl now has the pointer in the map to (e, a + d*256).
        ld a, c
        or a
        jp m, Lbcf2  ; Those elements with msb set to 1 are complex structures, and are handled 
                     ; separately.
        call Lbd91_add_element_to_map
        jr Lbcf5_continue
Lbcf2:
        call Lbd61_add_complex_structure_to_map
Lbcf5_continue:
    pop de
    pop hl
    jr Lbcd6_loop


; --------------------------------
; Adds warbases and factories to the map.
; - It also adds all the factories to the buildings list (but not the warbases)
; Input:
; - d: 0 if element x < 256, 1 if element x >= 256
; - hl: ptr to the elements to add.
; - ix: ptr to the factory list
; - iy: ptr to the warbase list
Lbcf9_add_warbases_and_factories_to_map:
    ld a, (hl)
    or a
    ret m  ; a 1 in the most significant bit indicates termination
    ld c, a  ; type
    inc hl
    ld e, (hl)  ; x (the most significant byte of x is passed as argument in d)
    inc hl
    ld a, (hl)
    ld b, a  ; y
    inc hl
    push hl
    push de
        ld hl, Ldd00_map
        add a, a
        add a, h
        ld h, a
        add hl, de  ; hl now points to the position in the map corresponding to the x, y, 
                    ; coordinates of the element
        ld a, c
        or a
        jr z, Lbd3e_warbase
        ld (iy + 0), e  ; x
        ld (iy + 1), d  ; x
        ld (iy + 2), b  ; y
        ld (iy + 3), c  ; type
        ld (iy + 4), 0
        inc iy
        inc iy
        inc iy
        inc iy
        inc iy
        push bc
        push hl
            ld a, #81  ; add a factory
            call Lbd61_add_complex_structure_to_map
        pop hl
        pop bc
        dec h
        dec h
        dec h
        dec h
        ; notice c still holds the type here
        call Lbc43_add_decoration_to_map
    pop de
    pop hl
    jr Lbcf9_add_warbases_and_factories_to_map
Lbd3e_warbase:
        ld (ix + 0), e  ; x
        ld (ix + 1), d  ; x
        ld (ix + 2), b  ; y
        ld (ix + 3), c  ; type
        ld (ix + 4), 0
        inc ix
        inc ix
        inc ix
        inc ix
        inc ix
        ld a, #80  ; add a warbase
        call Lbd61_add_complex_structure_to_map
    pop de
    pop hl
    jr Lbcf9_add_warbases_and_factories_to_map


; --------------------------------
; Adds a complex structure to the map buffer.
Lbd61_add_complex_structure_to_map:
    push hl
        ld hl, Lbf9c_map_complex_structure_ptrs
        and #7f  ; remove the msb
        call Ld348_get_ptr_from_table
        ex de, hl
    pop hl
Lbd6c_loop:
    ld a, (de)
    or a  ; element type
    call nz, Lbd91_add_element_to_map  ; if the structure is != 0, end.
    inc de
    ld a, (de)
    ld c, a  ; x
    inc de
    ld a, (de)
    ld b, a  ; y
    inc de
    or c
    ret z  ; if x == y == 0, we are done
    call Lbd7f_add_map_ptr_offset
    jr Lbd6c_loop


; --------------------------------
; Adds an (x, y) offset to a map pointer.
; Input:
; - hl: map pointer
; - c: offset in x
; - b: offset in y
Lbd7f_add_map_ptr_offset:
    push de
        ; hl += c
        ; extend c to 16 bits in de:
        ld e, c
        ld d, 0
        ld a, c
        or a
        jp p, Lbd8a_c_positive
        ld d, 255
Lbd8a_c_positive:
        add hl, de
        ld a, h
        add a, b
        add a, b
        ld h, a  ; h += b*2
    pop de
    ret


; --------------------------------
; Adds an element (building, terrain) to the map.
; This methods adds the desired element to a 2x2 grid, and marks the bottom-left with bit 5 to 0, 
; and the rest with bit 5 to 1.
; Input:
; - hl: map ptr
; - a: map element.
Lbd91_add_element_to_map:
    push de
        ld e, a
        ld bc, #0202
        push hl
Lbd97_loop_y:
            push bc
            push hl
Lbd99_loop_x:
                ld (hl), e  ; write the type of map element we have in this position.
                set 5, e  ; only the bottom-left corner has bit 5 set to 0, the rest have it to 1.
                inc hl
                djnz Lbd99_loop_x
            pop hl
            pop bc
            dec h  ; y -= 1
            dec h
            dec c
            jr nz, Lbd97_loop_y
        pop hl
    pop de
    ret


    ; --------------------------------
    ; Game map data:
    ; Each block of 3 bytes represents a map element: type, x, y.
    ; - Element types with the most significant bit set to 1 represent complex structures, which 
    ;   are specified
    ;   in "Lbf9c_map_complex_structure_ptrs".
    ; - A 0 indicates termination.
Lbda9_map_elements_part1:  ; elements with x < 256
    db #86, #0c, #01
    db #86, #0c, #09
    db #11, #10, #0e
    db #11, #20, #03
    db #82, #22, #0a
    db #05, #20, #0c
    db #04, #2a, #0a
    db #07, #2a, #0c
    db #06, #2a, #0e
    db #03, #2c, #0a
    db #09, #2c, #0c
    db #07, #2c, #0e
    db #83, #2e, #0a
    db #03, #30, #08
    db #04, #32, #08
    db #02, #36, #0c 
    db #06, #36, #0e
    db #03, #38, #0e
    db #12, #3f, #02
    db #12, #41, #02
    db #12, #46, #01
    db #11, #46, #0f
    db #11, #48, #0f
    db #87, #48, #02
    db #87, #53, #08
    db #06, #53, #02
    db #05, #53, #04
    db #83, #55, #02
    db #02, #55, #06
    db #04, #5b, #06
    db #07, #5d, #02
    db #03, #5d, #04 
    db #85, #5e, #0f
    db #88, #68, #09
    db #88, #6e, #09
    db #0d, #6e, #09
    db #85, #6a, #04
    db #85, #6c, #0d
    db #84, #79, #09
    db #11, #7f, #0c
    db #11, #81, #07
    db #85, #86, #04
    db #12, #85, #0b
    db #12, #85, #0d
    db #87, #97, #06
    db #82, #a5, #02
    db #83, #a7, #06
    db #83, #ad, #08
    db #83, #b3, #0a
    db #12, #bf, #08
    db #89, #bf, #03
    db #89, #c1, #08
    db #89, #bf, #0d
    db #89, #c7, #03
    db #89, #c7, #0d
    db #89, #cf, #03
    db #89, #c9, #08
    db #89, #cf, #0d
    db #12, #d1, #08
    db #89, #d7, #0d
    db #89, #df, #0d
    db #11, #e5, #0b
    db #84, #e9, #09
    db #12, #e9, #07
    db #82, #eb, #0a
    db #82, #f3, #0a
    db #02, #fb, #0c
    db #04, #fb, #0e
    db #03, #fd, #0e
    db #00

Lbe79_map_elements_part2:  ; elements with x >= 256
    db #83, #0e, #02
    db #83, #0c, #0a
    db #83, #10, #0a
    db #08, #08, #0e
    db #09, #0a, #0c
    db #0a, #0a, #0e
    db #08, #18, #0c
    db #0b, #18, #0e
    db #12, #21, #03
    db #11, #2b, #09
    db #12, #33, #0d
    db #11, #40, #0a
    db #11, #42, #0c
    db #11, #44, #0e
    db #12, #49, #0c
    db #85, #50, #05 
    db #85, #50, #09
    db #85, #58, #05
    db #85, #58, #09
    db #84, #60, #09
    db #12, #5e, #01
    db #12, #5e, #03
    db #11, #58, #01
    db #11, #52, #03
    db #11, #52, #0d
    db #11, #56, #0d
    db #11, #56, #0f
    db #11, #58, #0f
    db #11, #5a, #0f
    db #11, #5a, #0b
    db #8a, #64, #05
    db #11, #7b, #04 
    db #03, #7b, #0e
    db #04, #7d, #0c
    db #02, #7d, #0e
    db #82, #7f, #0a
    db #05, #87, #0c
    db #02, #87, #0e
    db #04, #89, #0e
    db #12, #8a, #01
    db #11, #91, #0f
    db #12, #99, #01
    db #88, #96, #05
    db #88, #99, #09
    db #88, #99, #0d
    db #87, #a4, #08
    db #87, #a8, #02
    db #87, #ac, #08
    db #87, #b0, #02
    db #09, #b4, #0e
    db #83, #b6, #0a
    db #83, #bc, #0a
    db #04, #c0, #0a
    db #03, #c2, #0a
    db #02, #c2, #0c
    db #88, #c5, #03
    db #11, #d0, #0a
    db #11, #d3, #0d
    db #8a, #de, #01
    db #8a, #dc, #03
    db #8a, #da, #05
    db #8a, #da, #09
    db #8a, #dc, #0b
    db #8a, #de, #0d
    db #8a, #e0, #0f
    db #8a, #e0, #05
    db #86, #f7, #01
    db #86, #f7, #09
    db #00

    ; Warbases and factories:
    ; 0 are warbases, and 1 - 6 are factories
Lbf46_warbases_factories_part1:
    db #00, #16, #09
    db #04, #27, #06
    db #06, #35, #03
    db #01, #3e, #0a
    db #05, #4f, #03
    db #03, #61, #03
    db #02, #7d, #03
    db #06, #8c, #0b
    db #01, #a0, #05
    db #03, #b4, #03
    db #04, #d9, #03
    db #05, #e3, #09
    db #06, #f1, #03
    db #ff

Lbf6e_warbases_factories_part2:
    db #00, #05, #08
    db #03, #1a, #03
    db #01, #20, #0d
    db #02, #28, #03
    db #04, #37, #07
    db #06, #42, #03
    db #00, #71, #08
    db #03, #82, #03
    db #05, #91, #07 
    db #01, #a0, #03
    db #02, #b4, #05
    db #04, #be, #03
    db #05, #c8, #0a
    db #06, #d2, #03
    db #00, #ee, #08
    db #ff

Lbf9c_map_complex_structure_ptrs:
    dw Lbfb2_warbase
    dw Lbfe2_factory
    dw Lbff4
    dw Lc018
    dw Lc03c
    dw Lc048
    dw Lc054
    dw Lc060
    dw Lc06c
    dw Lc078
    dw Lc084

    ; Each complex structure is a list of map elements. Termination is marked by an
    ; element with x == y == 0.
Lbfb2_warbase:
    db #00, #fc, #fc
    db #10, #00, #fe
    db #10, #02, #05
    db #0f, #00, #fe
    db #0f, #00, #fe
    db #0f, #00, #fe
    db #10, #02, #05
    db #0f, #00, #fe
    db #10, #00, #fe
    db #10, #02, #05
    db #0f, #00, #fe
    db #0f, #00, #fe
    db #0f, #00, #fe
    db #10, #02, #03
    db #10, #00, #fe
    db #10, #00, #00

Lbfe2_factory:
    db #00, #fe, #00
    db #0f, #00, #fe
    db #10, #02, #00
    db #10, #02, #00
    db #10, #00, #02
    db #0f, #00, #00

Lbff4:
    db #02, #02, #00
    db #03, #02, #00
    db #04, #02, #00
    db #05, #fa, #02
    db #04, #02, #00
    db #05, #02, #00
    db #02, #02, #00
    db #03, #fa, #02
    db #03, #02, #00
    db #02, #02, #00
    db #05, #02, #00
    db #04, #00, #00

Lc018:
    db #08, #02, #00
    db #09, #02, #00
    db #0a, #02, #00
    db #0b, #fa, #02
    db #0a, #02, #00
    db #0b, #02, #00
    db #08, #02, #00
    db #09, #fa, #02
    db #09, #02, #00
    db #08, #02, #00
    db #0b, #02, #00
    db #0a, #00, #00

Lc03c:
    db #12, #00, #02
    db #12, #00, #02
    db #12, #00, #02
    db #12, #00, #00

Lc048:
    db #12, #02, #00
    db #12, #02, #00
    db #12, #02, #00
    db #12, #00, #00

Lc054:
    db #15, #00, #02
    db #15, #00, #02
    db #15, #00, #02
    db #15, #00, #00

Lc060:
    db #0c, #00, #02
    db #0d, #00, #02
    db #0d, #00, #02
    db #0e, #00, #00

Lc06c:
    db #0c, #02, #00
    db #0d, #02, #00
    db #0d, #02, #00
    db #0e, #00, #00

Lc078:
    db #11, #02, #00
    db #11, #02, #00
    db #11, #02, #00
    db #11, #00, #00

Lc084:
    db #11, #02, #00
    db #12, #02, #00
    db #11, #00, #00


    ds #c100 - $, 0  ; 115 bytes of empty space until the game code continues.


; --------------------------------
Lc100_title_screen:
    call Ld0b9_clear_screen
    call Lc1e3_draw_game_title
Lc106_title_screen_redraw_options:
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_ATTRIBUTE, #46
        db CMD_SET_SCALE, #21
        db CMD_SET_POSITION, #0b, #08
        db "0..START GAME"
        db CMD_SET_SCALE, #00
        db CMD_END
    ; Script end:
    ld c, 1
    call Lc336_highlight_if_selected
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "1..KEYBOARD"
        db CMD_END
    ; Script end:
    ld c, 2
    call Lc336_highlight_if_selected
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "2..KEMPSTON J/S"
        db CMD_END
    ; Script end:
    ld c, 3
    call Lc336_highlight_if_selected
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "3..INTERFACE 2"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db CMD_SET_ATTRIBUTE, #46
        db "4..REDEFINE KEYS"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db "5..LOAD SAVED GAME"
        db CMD_END
    ; Script end:
Lc192_wait_for_key_not_pressed_loop:
    halt
    call Lc820_title_color_cycle
    call L028e_BIOS_POLL_KEYBOARD
    ld a, e
    or a
    jp p, Lc192_wait_for_key_not_pressed_loop
    call Lc4a7_title_music_loop
Lc1a1_wait_for_key_press_loop:
    halt
    call Lc820_title_color_cycle
    call L028e_BIOS_POLL_KEYBOARD
    ld a, e
    or a
    jp m, Lc1a1_wait_for_key_press_loop
    ld hl, L0205_BIOS_KEYCODE_TABLE
    add a, l
    ld l, a
    ld a, (hl)
    cp '5'
    jr z, Lc1fd_select_load_saved_game
    cp '0'
    jr z, Lc1d1_select_start_game
    cp '1'
    jr z, Lc1d3_select_keyboard
    cp '2'
    jr z, Lc1d7_select_kempston
    cp '3'
    jr z, Lc1db_select_interface2
    cp '4'
    jr nz, Lc1a1_wait_for_key_press_loop
    call Lc34a_redefine_keys
    jp Lc100_title_screen

Lc1d1_select_start_game:
    xor a
    ret

Lc1d3_select_keyboard:
    ld a, INPUT_KEYBOARD
    jr Lc1dd_select_input

Lc1d7_select_kempston:
    ld a, INPUT_KEMPSTON
    jr Lc1dd_select_input

Lc1db_select_interface2:
    ld a, INPUT_INTERFACE2
Lc1dd_select_input:
    ld (Ld3e4_input_type), a
    jp Lc106_title_screen_redraw_options


; --------------------------------
Lc1e3_draw_game_title:
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #01, #0a
        db CMD_SET_ATTRIBUTE, #47
        db CMD_SET_SCALE, #32
        db "NETHER"
        db CMD_SET_POSITION, #05, #0b
        db "EARTH"
        db CMD_END
    ; Script end:
    ret


; --------------------------------
Lc1fd_select_load_saved_game:
    call Lc1e3_draw_game_title
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #16, #07
        db CMD_SET_ATTRIBUTE, #45
        db CMD_SET_SCALE, #21
        db "PRESS PLAY ON TAPE "
        db CMD_END
    ; Script end:
    ld a, 2
    out (ULA_PORT), a  ; change border color
    ld ix, L5b00  ; Address to store the data read from tape
    ld de, 2  ; read 2 bytes (checksum)
    xor a
    scf
    inc d
    ex af, af'
    dec d
    di
    call L0562_BIOS_READ_FROM_TAPE_SKIP_TESTS

    ld ix, Ld92b_save_game_start  ; Address to store the data read from tape
    ld de, Lfdfc_save_game_end - Ld92b_save_game_start  ; read 9425 bytes (the whole RAM space, up 
                                                        ; to the interrupt table!)
    xor a
    scf
    inc d
    ex af, af'
    dec d
    di
    call L0562_BIOS_READ_FROM_TAPE_SKIP_TESTS

    xor a
    out (ULA_PORT), a  ; border to black

    ; Make sure checksum is correct:
    call Lc30f_compute_checksum
    ld hl, (L5b00)
    and a
    sbc hl, de
    ld a, h
    or l
    jr nz, Lc269_checksum_does_not_match
    ld hl, Ld92b_save_game_start
    ld de, Ld7d3_bullets
    ld bc, MAX_BULLETS * BULLET_STRUCT_SIZE
    ldir  ; Restore the bullet state from the reading buffer.
    ld de, Lff01_building_decorations
    ld bc, 168
    ldir
    ei
    or 1
    ret


Lc269_checksum_does_not_match:
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #16, #02
        db CMD_SET_ATTRIBUTE, #47
        db CMD_SET_SCALE, #22
        db "LOADING ERROR!"
        db CMD_END
    ; Script end:
    ld a, 250
    call Lccac_beep
    call Lc325_wait_for_key
    jp La600_start


; --------------------------------
; Saves the current game state to tape
Lc28d_save_game:
    ld hl, Ld59c_empty_interrupt
    ld (Lfdfe_interrupt_pointer), hl
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #16, #00
        db CMD_SET_ATTRIBUTE, #45
        db "PRESS RECORD AND PLAY "
        db CMD_NEXT_LINE
        db "     THEN ANY KEY     "
        db CMD_END
    ; Script end:
    call Lc325_wait_for_key
    ld a, 1
    ld (Lfd52_update_radar_buffer_signal), a
    ld hl, Ld7d3_bullets
    ld de, Ld92b_save_game_start
    ld bc, MAX_BULLETS * BULLET_STRUCT_SIZE
    ldir  ; save the bullet state to a buffer for saving the game. Potential optimization: put the 
          ; bullets here to begin with.
    ld hl, Lff01_building_decorations
    ld bc, 168
    ldir
    di
    call Lc30f_compute_checksum
    ld (L5b00), de
    ld hl, 2304  ; Data timing for saving bytes to disc
    ld ix, L5b00
    ld de, 2  ; save 2 bytes to tape (checksum)
    xor a
    scf
    call L04d0_BIOS_CASSETTE_SAVE_SKIP_TESTS
    ld hl, 2304  ; Data timing for saving bytes to disc
    ld ix, Ld92b_save_game_start
    ld de, Lfdfc_save_game_end - Ld92b_save_game_start  ; save 9425 bytes to tape
    xor a
    scf
    call L04d0_BIOS_CASSETTE_SAVE_SKIP_TESTS
    xor a
    out (ULA_PORT), a  ; border black
    ei
    ret


; --------------------------------
; Computes the checksum of the whole block of data that is saved
; in a save game (9425 bytes)
Lc30f_compute_checksum:
    ld hl, Ld92b_save_game_start
    ld bc, Lfdfc_save_game_end - Ld92b_save_game_start
    ld de, 0
Lc318:
    ld a, (hl)
    inc hl
    add a, e
    ld e, a
    jr nc, Lc31f
    inc d
Lc31f:
    dec bc
    ld a, b
    or c
    jr nz, Lc318
    ret


; --------------------------------
; Waits until the user presses any key
Lc325_wait_for_key:
    ; Wait until no key is pressed:
Lc325_wait_for_key_loop1:
    xor a
    in a, (ULA_PORT)  ; a = high byte, ULA_PORT = low byte
    cpl
    and 31
    jr nz, Lc325_wait_for_key_loop1
    ; Wait until the user presses any key:
Lc32d_wait_for_key_loop2:
    xor a
    in a, (ULA_PORT)  ; a = high byte, ULA_PORT = low byte
    cpl
    and 31
    jr z, Lc32d_wait_for_key_loop2
    ret


; --------------------------------
Lc336_highlight_if_selected:
    ld a, (Ld3e4_input_type)
    cp c
    jr z, Lc343_highlight
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_ATTRIBUTE, #46
        db CMD_END
    ; Script end:
    ret
Lc343_highlight:
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_ATTRIBUTE, #45
        db CMD_END
    ; Script end:
    ret


; --------------------------------
Lc34a_redefine_keys:
    call Ld0b9_clear_screen
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #02, #09
        db CMD_SET_ATTRIBUTE, #47
        db CMD_SET_SCALE, #21
        db "REDEFINE KEYS"
        db CMD_SET_POSITION, #05, #03
        db CMD_SET_SCALE, #00
        db CMD_END
    ; Script end:
Lc36a_wait_for_no_key_pressed_loop:
    call L028e_BIOS_POLL_KEYBOARD
    ld a, e
    or a
    jp p, Lc36a_wait_for_no_key_pressed_loop
    ; Clear all the key definitions:
    ld hl, Ld3cc_key_pause
    ld de, Ld3cc_key_pause+1
    ld bc, 23
    ld (hl), 0
    ldir
    call Lc40c_print_press_key_for
    ; Script start:
        db "   UP"
        db CMD_END
    ; Script end:
    ld hl, Ld3d8_key_up+2
    call Lc427_redefine_one_key
    call Lc40c_print_press_key_for
    ; Script start:
        db " DOWN"
        db CMD_END
    ; Script end:
    ld hl, Ld3db_key_down+2
    call Lc427_redefine_one_key
    call Lc40c_print_press_key_for
    ; Script start:
        db " LEFT"
        db CMD_END
    ; Script end:
    ld hl, Ld3de_key_left+2
    call Lc427_redefine_one_key
    call Lc40c_print_press_key_for
    ; Script start:
        db "RIGHT"
        db CMD_END
    ; Script end:
    ld hl, Ld3e1_key_right+2
    call Lc427_redefine_one_key
    call Lc40c_print_press_key_for
    ; Script start:
        db " FIRE"
        db CMD_END
    ; Script end:
    ld hl, Ld3d5_key_fire+2
    call Lc427_redefine_one_key
    call Ld470_execute_command_3_next_line
    call Lc40c_print_press_key_for
    ; Script start:
        db "PAUSE"
        db CMD_END
    ; Script end:
    ld hl, Ld3cc_key_pause+2
    call Lc427_redefine_one_key
    call Lc40c_print_press_key_for
    ; Script start:
        db "ABORT"
        db CMD_END
    ; Script end:
    ld hl, Ld3cf_key_abort+2
    call Lc427_redefine_one_key
    call Lc40c_print_press_key_for
    ; Script start:
        db " SAVE"
        db CMD_END
    ; Script end:
    ld hl, Ld3d2_key_save+2
    call Lc427_redefine_one_key
Lc3fa:
    call L028e_BIOS_POLL_KEYBOARD
    ld a, e
    or a
    jp p, Lc3fa
    ld bc, 0
Lc405:
    dec bc
    nop
    ld a, c
    or b
    jr nz, Lc405
    ret


; --------------------------------
Lc40c_print_press_key_for:
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_NEXT_LINE    
        db CMD_NEXT_LINE    
        db CMD_SET_ATTRIBUTE, #46
        db "PRESS KEY FOR "
        db CMD_SET_ATTRIBUTE, #45
        db CMD_END
    ; Script end:
    jp Ld42d_execute_ui_script


; --------------------------------
Lc427_redefine_one_key:
    push hl
        call Ld42d_execute_ui_script
        ; Script start:
            db "  "
            db CMD_SET_ATTRIBUTE, #46
            db CMD_END
        ; Script emd:
Lc430_wait_for_key_pressed_loop:
        call L028e_BIOS_POLL_KEYBOARD
        ld a, e
        or a
        jp m, Lc430_wait_for_key_pressed_loop
        ld hl, L0205_BIOS_KEYCODE_TABLE
        add a, l
        ld l, a
        ld a, (hl)
        ld d, a
        ld hl, Ld3cc_key_pause+2
        ld b, 8
Lc444_duplicate_key_check_loop:
        cp (hl)  ; If they key is already used, ignore
        jr z, Lc430_wait_for_key_pressed_loop
        inc hl
        inc hl
        inc hl
        djnz Lc444_duplicate_key_check_loop
    pop hl
    ld (hl), a  ; assign the key haracter
    ld a, e
    and #07
    ld c, a
    srl e
    srl e
    srl e
    ld b, e
    inc b
    ld a, 32
Lc45c:
    rrca
    djnz Lc45c
    dec hl
    ld (hl), a
    ld b, c
    inc b
    xor a
    dec a
Lc465:
    rra
    djnz Lc465
    dec hl
    ld (hl), a
    ld a, d
    cp 14
    jr nz, Lc47a_not_sym_shift
    call Ld42d_execute_ui_script
    ; Script start:
        db "SYM SH"
        db CMD_END
    ; Script end:
    ret
Lc47a_not_sym_shift:
    cp 13
    jr nz, Lc488_not_enter
    call Ld42d_execute_ui_script
    ; Script start:
        db "ENTER"
        db CMD_END
    ; Script end:
    ret
Lc488_not_enter:
    cp 227
    jr nz, Lc498_not_caps_shift
    call Ld42d_execute_ui_script
    ; Script start:
        db "CAPS SH"
        db CMD_END
    ; Script end:
    ret
Lc498_not_caps_shift:
    cp 32
    jp nz, Ld427_draw_character_saving_registers
    call Ld42d_execute_ui_script
    ; Script start:
        db "SPACE"
        db CMD_END
    ; Script end:
Lc4a6:
Lc4a6_music_empty_event:  ; event 0
    ret


; --------------------------------
; Waits until the player presses any number in the keyboard.
; While waiting, the title color is cycled, and music is played
Lc4a7_title_music_loop:
    di
        ld (Lfd08_stack_ptr_buffer), sp  ; store the stack pointer
        ld hl, Lc4fd_title_music_loop_interrupt
        ld (Lfdfe_interrupt_pointer), hl
        ld hl, Lc678_music_event_table_channel1
        ld de, Lc702_music_event_table_channel2
        ld bc, #0101  ; duration of the current event in the music channels (c = 1, b = 1 means 
                      ; they will be reevaluated in the next frame, in 
                      ; "Lc4fd_title_music_loop_interrupt")
        exx
        ld hl, Lc665_percussion_loops
    ei
    ld c, 1
    halt
Lc4c3:
    push af
        ld a, (Lfd0c_keyboard_state)  ; Question: what is the effect of this?
        ld (Lfd0c_keyboard_state), a
    pop af
Lc4cb:
    dec d  ; note: undefined the first time we enter this function
    jp nz, Lc4e0
    ; Produce a wave for channel 2: the events of the channel modify these parameters to produce 
    ; the right wave.
Lc4d0_selfmodifying: equ $ + 1
    ld d, 55  ; mdl:self-modifying
Lc4d2_selfmodifying: equ $ + 1
    ld a, 24  ; mdl:self-modifying
    out (ULA_PORT), a  ; produce sound (wave front up)
Lc4d6_selfmodifying: equ $ + 1
    ld a, 13  ; mdl:self-modifying
Lc4d7:
    dec a
    jp nz, Lc4d7
    out (ULA_PORT), a  ; produce sound (wave front down as a == 0)
    jp Lc4e8
Lc4e0:
    push af
        ld a, (Lfd0c_keyboard_state)  ; Question: what is the effect of this?
        ld (Lfd0c_keyboard_state), a
    pop af
Lc4e8:
    dec e
    jp nz, Lc4c3
    ; Produce a wave for channel 1: the events of the channel modify these parameters to produce 
    ; the right wave.
Lc4ed_selfmodifying: equ $ + 1
    ld e, 124  ; mdl:self-modifying
Lc4ef_selfmodifying: equ $ + 1
    ld a, 24  ; mdl:self-modifying
    out (ULA_PORT), a  ; produce sound (wave front up)
Lc4f3_selfmodifying: equ $ + 1
    ld a, 31  ; mdl:self-modifying
Lc4f4:
    dec a
    jp nz, Lc4f4
    out (ULA_PORT), a  ; produce sound (wave front down as a == 0)
    jp Lc4cb


; --------------------------------
Lc4fd_title_music_loop_interrupt:
    push af
        dec c
        call z, Lc5db_music_percussion
        exx
            dec c
            call z, Lc528_music_next_event_channel1  ; if the duration of the previous event 
                                                     ; reached 0, new event!
            dec b
            call z, Lc53b_music_next_event_channel2  ; if the duration of the previous event 
                                                    ; reached 0, new event!
            call Lc820_title_color_cycle
            ld a, 231  ; read 4th and 5th keyboard rows (all the numbers).
            in a, (ULA_PORT)  ; a = high byte, ULA_PORT = low byte.
            cpl
            and 31
            jr nz, Lc51b  ; If any number was pressed, exit the title music loop.
        exx
    pop af
    ei
    ret
Lc51b:
    di
        ld sp, (Lfd08_stack_ptr_buffer)  ; restore the stack pointer that was stored when entering 
                                         ; "Lc4a7_title_music_loop".
        ld hl, Ld59c_empty_interrupt
        ld (Lfdfe_interrupt_pointer), hl
    ei
    ret  ; this effectively returns from "Lc4a7_title_music_loop".


; --------------------------------
; Reads the next event from the music event table 1 and executes it
; input:
; - hl: next event
Lc528_music_next_event_channel1:
    ld a, (hl)
    cp 9
    jr c, Lc54f_music_event_jump_table_channel1
    ld (Lc4ed_selfmodifying), a
    rrca
    rrca
    and #3f
    ld (Lc4f3_selfmodifying), a
    inc hl
    ld c, (hl)
    inc hl
    ret


; --------------------------------
; Reads the next event from the music event table 2 and executes it
; input:
; - de: next event
Lc53b_music_next_event_channel2:
    ld a, (de)
    cp 9
    jr c, Lc56e_music_event_jump_table_channel2
    ld (Lc4d0_selfmodifying), a
    rrca
    rrca
    and #3f
    ld (Lc4d6_selfmodifying), a
    inc de
    ld a, (de)
    ld b, a
    inc de
    ret


; --------------------------------
Lc54f_music_event_jump_table_channel1:
    push hl
    call Lc65b_jump_table_jump
    jp Lc4a6_music_empty_event
    jp Lc5a7_music_channel1_jump
    jp Lc58d_music_channel1_call
    jp Lc5cc_set_percussion_ptr
    jp Lc635_activate_channel1
    jp Lc63f_silence_channel1
    jp Lc5bb_music_channel1_ret
    jp Lc5cc_set_percussion_ptr
    jp Lc5cc_set_percussion_ptr


; --------------------------------
Lc56e_music_event_jump_table_channel2:
    push hl
    call Lc65b_jump_table_jump
    jp Lc4a6_music_empty_event
    jp Lc5b0_music_channel2_jump
    jp Lc599_music_channel2_call
    jp Lc5cc_set_percussion_ptr
    jp Lc648_activate_channel2
    jp Lc652_silence_channel2
    jp Lc5c3_music_channel2_ret
    jp Lc5cc_set_percussion_ptr
    jp Lc5cc_set_percussion_ptr


; --------------------------------
; Event 2
Lc58d_music_channel1_call:
    pop hl
    inc hl
    ld a, (hl)
    inc hl
    ld (Lfd54_music_channel1_ret_address), hl
    ld h, (hl)
    ld l, a
    jp Lc528_music_next_event_channel1


; --------------------------------
; Event 2
Lc599_music_channel2_call:
    pop hl
    ex de, hl
        inc hl
        ld a, (hl)
        inc hl
        ld (Lfd56_music_channel2_ret_address), hl
        ld h, (hl)
        ld l, a
    ex de, hl
    jp Lc53b_music_next_event_channel2


; --------------------------------
; Event 1
Lc5a7_music_channel1_jump:
    pop hl
    inc hl
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    jp Lc528_music_next_event_channel1


; --------------------------------
; Event 1
Lc5b0_music_channel2_jump:
    pop hl
    ex de, hl
    inc hl
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    ex de, hl
    jp Lc53b_music_next_event_channel2


; --------------------------------
; Event 6
Lc5bb_music_channel1_ret:
    pop hl
    ld hl, (Lfd54_music_channel1_ret_address)
    inc hl
    jp Lc528_music_next_event_channel1


; --------------------------------
; Event 6
Lc5c3_music_channel2_ret:
    pop hl
    ld de, (Lfd56_music_channel2_ret_address)
    inc de
    jp Lc53b_music_next_event_channel2


; --------------------------------
; Event 3, 7 or 8
Lc5cc_set_percussion_ptr:
    pop hl
    inc hl
    ld a, (hl)
    inc hl
    exx
        ld l, a
    exx
    ld a, (hl)
    inc hl
    exx
        ld h, a
    exx
    jp Lc528_music_next_event_channel1


; --------------------------------
Lc5db_music_percussion: 
    ld a, (hl)
    inc hl
    cp 1
    jr z, Lc601_go_to  ; command == 1: go-to
    ld c, a  ; Otherwise, repeat the following command for "a" steps
    ld a, (hl)
    inc hl
    cp 2
    jr z, Lc616_tone_drum  ; 2: beep
    and a
    jr z, Lc608_drum1  ; 0: noisy beep
    ; any number != 0 and != 2:
    push hl
        ld h, 0  ; read 80 random bytes from the BIOS
        ld b, 80
Lc5f0_drum2:
        ld a, (hl)
        and 24  ; sets all bits to 0 except those referring to MIC/EAR (to produce sound).
        out (ULA_PORT), a  ; change MIC/EAR state (to produce sound)
        ld a, b
        cpl
        and 63
Lc5f9_wait_pulse_on:
        dec a
        jr nz, Lc5f9_wait_pulse_on
        inc hl
        djnz Lc5f0_drum2
    pop hl
    ret


; --------------------------------
Lc601_go_to:
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    jp Lc5db_music_percussion


; --------------------------------
Lc608_drum1:
    push hl
        ld h, 8
        ld b, 96
Lc60d:
        ld a, (hl)  ; This is just reading a random byte from the BIOS (so, probably to produce 
                    ; noise).
        and 24
        out (ULA_PORT), a  ; change MIC/EAR state (to produce sound)
        djnz Lc60d
    pop hl
    ret


; --------------------------------
Lc616_tone_drum:
    ld a, (hl)
    inc hl
    push hl
        ld b, 48  ; number of pulses the sound wave will have
        ld l, a
        rrca
        ld h, a
Lc61e_wave_loop:
        xor a
        out (ULA_PORT), a  ; change MIC/EAR state (sound off)
        dec l
        ld a, l
Lc623_wait_pulse_off:
        dec a
        jr nz, Lc623_wait_pulse_off
        ld a, 24
        out (ULA_PORT), a  ; change MIC/EAR state (to produce sound)
        ld a, 4
        add a, h
        ld h, a
Lc62e_wait_pulse_on:
        dec a
        jr nz, Lc62e_wait_pulse_on
        djnz Lc61e_wave_loop
    pop hl
    ret


; --------------------------------
; Event 4
Lc635_activate_channel1:
    pop hl
    ld a, 24
    ld (Lc4ef_selfmodifying), a
    inc hl
    jp Lc528_music_next_event_channel1


; --------------------------------
; Event 5
Lc63f_silence_channel1:
    pop hl
    xor a
    ld (Lc4ef_selfmodifying), a
    inc hl
    jp Lc528_music_next_event_channel1


; --------------------------------
; Event 4
Lc648_activate_channel2:
    pop hl
    ld a, 24
    ld (Lc4d2_selfmodifying), a
    inc de
    jp Lc53b_music_next_event_channel2


; --------------------------------
; Event 5
Lc652_silence_channel2:
    pop hl
    xor a
    ld (Lc4d2_selfmodifying), a
    inc de
    jp Lc53b_music_next_event_channel2


; --------------------------------
; Gets the pointer to the list of jumps from the stack, selects the pointer index "a", and jumps
; Input:
; - stack: jump table pointer
; - a: index of the function to jump to
Lc65b_jump_table_jump:
    ld l, a
    add a, a
    add a, l  ; a = a*3
    pop hl  ; get the pointer to the jump table
    ; hl += a:
    add a, l
    ld l, a
    jr nc, Lc664
    inc h
Lc664:
    jp hl


; --------------------------------
; Title Music:
; Music in Nether Earth is defined in a scripting language with a series of commands, and has 3 
; channels:
; - one channel just contains percussion loops
; - the other two channels (channel 1, channel 2) contain the notes.
; For example, command "2" is a "call" to a music subroutine, "3" is a "jump" to a different
; part of the score, etc. These commands basically index the functions in two jumptables:
; "Lc54f_music_event_jump_table_channel1" and "Lc54f_music_event_jump_table_channel2".
Lc665_percussion_loops:
    db #20, #00  ; 32 steps of drum 1
    db #01, #65, #c6  ; go-to #c665
    db #20, #00  ; 32 steps of drum 1  [I think this is unused]
Lc66c:
    db #10, #01  ; 16 steps of drum 2
    db #08, #00  ; 8 steps of drum 1
    db #08, #00  ; 8 steps of drum 1
    db #20, #02, #30  ; 32 steps of clean beep drum instrument
    db #01, #6c, #c6  ; go-to #c66c

Lc678_music_event_table_channel1:
    db #03, #65, #c6
    db #02, #bd, #c6  ; call Lc6bd
    db #02, #bd, #c6  ; call Lc6bd
    db #02, #bd, #c6  ; call Lc6bd
    db #02, #bd, #c6  ; call Lc6bd
    db #03, #6c, #c6
    db #02, #cc, #c6  ; call Lc6cc
    db #02, #cc, #c6  ; call Lc6cc
    db #02, #dd, #c6  ; call Lc6dd
    db #02, #dd, #c6  ; call Lc6dd
    db #02, #dd, #c6  ; call Lc6dd
    db #02, #dd, #c6  ; call Lc6dd
    db #02, #dd, #c6  ; call Lc6dd
    db #02, #dd, #c6  ; call Lc6dd
    db #02, #dd, #c6  ; call Lc6dd
    db #02, #dd, #c6  ; call Lc6dd
    db #02, #cc, #c6  ; call Lc6cc
    db #02, #cc, #c6  ; call Lc6cc
    db #02, #cc, #c6  ; call Lc6cc
    db #02, #cc, #c6  ; call Lc6cc
    db #02, #cc, #c6  ; call Lc6cc
    db #03, #65, #c6
    db #01, #78, #c6  ; jump back to the beginning
Lc6bd:
    db #7c, #10, #05, #7c, #08, #04, #7c, #10, #05, #7c, #40, #52, #18, #04
    db #06  ; ret
Lc6cc:
    db #7c, #40, #6e, #40, #68, #40, #5d, #40, #7c, #40, #6e, #40, #68, #40, #5d, #40
    db #06  ; ret
Lc6dd:
    db #7c, #08, #05, #7c, #08, #04, #7c, #08, #05, #7c, #08, #04, #7c, #08, #8b, #08
    db #93, #08, #a5, #08, #ba, #08, #a5, #08, #93, #08, #8b, #08, #7c, #08, #8b, #08
    db #93, #08, #a5, #08
    db #06  ; ret

Lc702_music_event_table_channel2:
    db #02, #89, #c7  ; call Lc789
    db #02, #89, #c7  ; call Lc789
    db #02, #89, #c7  ; call Lc789
    db #02, #89, #c7  ; call Lc789
    db #02, #aa, #c7  ; call Lc7aa
    db #02, #aa, #c7  ; call Lc7aa
    db #02, #aa, #c7  ; call Lc7aa
    db #02, #aa, #c7  ; call Lc7aa
    db #05
    db #02, #aa, #c7  ; call Lc7aa
    db #04
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #d2, #c7  ; call Lc7d2
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #d2, #c7  ; call Lc7d2
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #d2, #c7  ; call Lc7d2
    db #02, #c5, #c7  ; call Lc7c5
    db #3e, #20, #37, #20
    db #02, #aa, #c7  ; call Lc7aa
    db #02, #aa, #c7  ; call Lc7aa
    db #02, #df, #c7  ; call Lc7df
    db #02, #df, #c7  ; call Lc7df
    db #02, #df, #c7  ; call Lc7df
    db #02, #df, #c7  ; call Lc7df
    db #02, #89, #c7  ; call Lc789
    db #02, #89, #c7  ; call Lc789
    db #02, #89, #c7  ; call Lc789
    db #02, #89, #c7  ; call Lc789
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #c5, #c7  ; call Lc7c5
    db #02, #89, #c7  ; call Lc789
    db #02, #89, #c7  ; call Lc789
    db #02, #89, #c7  ; call Lc789
    db #02, #89, #c7  ; call Lc789
    db #01, #02, #c7  ; jump back to the beginning
Lc789:
    db #37, #10, #05, #37, #08, #04, #37, #10, #05, #37, #08, #04, #29, #08, #2e, #08
    db #29, #08, #2e, #08, #29, #08, #2e, #08, #29, #08, #2e, #08, #37, #08, #3e, #08
    db #06  ; ret
Lc7aa:
    db #29, #10, #2e, #10, #31, #10, #37, #10, #3e, #20, #49
    db #10, #3e, #10, #45, #20, #2e, #20, #29, #10, #2e, #10, #34, #10, #2e, #10
    db #06  ; ret
Lc7c5:
    db #3e, #10, #52, #08, #7c, #08, #3e, #10, #52, #08, #7c, #08
    db #06  ; ret
Lc7d2:
    db #45, #10, #5d, #08, #8b, #08, #45, #10, #5d, #08, #8b, #08
    db #06  ; ret
Lc7df:
    db #29, #04, #2e, #04, #34, #04, #37, #04, #3e, #04, #45, #04, #49, #04, #52, #04
    db #5d, #04, #68, #04, #6e, #04, #7c, #04, #8b, #04, #93, #04, #a5, #04, #ba, #04
    db #29, #04, #2e, #04, #34, #04, #37, #04, #3e, #04, #45, #04, #49, #04, #52, #04
    db #5d, #04, #68, #04, #6e, #04, #7c, #04, #8b, #04, #93, #04, #a5, #04, #ba, #04
    db #06  ; ret


; --------------------------------
Lc820_title_color_cycle:
    push bc
    push hl
        ld hl, L5800_VIDEOMEM_ATTRIBUTES + 32 + 10
        ld a, (Lfd33_title_color)
        inc a
        and #0f
        ld (Lfd33_title_color), a
        rrca
        jr c, Lc846
        or 64
        ld bc, #0c07  ; change the color of 12 columns and 7 rows
Lc836:
        push bc
Lc837:
            ld (hl), a
            inc hl
            djnz Lc837
            ld b, a
            ld a, 20
            call Ld351_add_hl_a
            ld a, b
        pop bc
        dec c
        jr nz, Lc836
Lc846:
    pop hl
    pop bc
    ret


; --------------------------------
; Checks if the player has less than the maximum number of robots, and if so, jumps to the robot 
; construction screen with "iy" pointing to a free robot structure.
Lc849_robot_construction_if_possible:
    ld iy, Lda00_player1_robots
    ld de, 16
    ld b, MAX_ROBOTS_PER_PLAYER
Lc852_loop:
    ld a, (iy + 1)
    or a
    jr z, Lc85d_robot_construction
    add iy, de
    djnz Lc852_loop
    ret


; --------------------------------
; Robot construction screen:
; input:
; - iy: pointer to the robot struct that we will be editing.
Lc85d_robot_construction:
    di
    ld hl, Ld59c_empty_interrupt
    ld (Lfdfe_interrupt_pointer), hl
    ei
    call Ld0b9_clear_screen
    ld b, 8  ; there are 8 pieces to draw
    ld de, #57f0  ; Video pointer: (x, y) = (128, 191)  (bottom center of the screen)
Lc86d_robot_construction_draw_piece_loop:
    push bc
    push de
        ld a, 8
        sub b
        add a, a
        add a, a  ; a contains the index of the piece we want to draw in the 
                  ; Ld6c8_piece_direction_graphic_indices table
        inc a  ; we add 1 to select the index for the south-west direction
        ld hl, Ld6c8_piece_direction_graphic_indices
        call Ld351_add_hl_a
        ld a, (hl)  ; get the graphic index
        add a, a
        inc a
        ld hl, Ld740_isometric_graphic_pointers
        call Ld348_get_ptr_from_table
        ld c, (hl)
        inc hl
        ld b, (hl)
        inc hl
        ld a, b
        add a, a
        call Ld351_add_hl_a
        dec c
        ld a, c
        ; Limit the height to draw to 24 pixels (some pieces are taller than that):
        cp 24
        jr c, Lc895_height_calculated
        ld c, 24
Lc895_height_calculated:
        ; Draw a piece sprite:
        call Ld315_draw_masked_sprite_bottom_up
    pop de
    pop bc
    ; move the drawing coordinates 24 pixels up:
    ld a, e
    sub 96
    ld e, a
    jr nc, Lc8a4
    ld a, d
    sub 8
    ld d, a
Lc8a4:
    djnz Lc86d_robot_construction_draw_piece_loop

    ; Set the part of the screen where the robot under construction will be drawn to yellow:
    ld bc, #0409
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + 15*32
Lc8ac_loop_y:
    push bc
Lc8ad_loop_x:
        ld (hl), #46  ; bright, black paper, ink color 6 (yellow)
        inc hl
        djnz Lc8ad_loop_x
        ld a, 28
        call Ld351_add_hl_a
    pop bc
    dec c
    jr nz, Lc8ac_loop_y

    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_SCALE, #22
        db CMD_SET_ATTRIBUTE, #47
        db CMD_SET_POSITION, #00, #03
        db "ROBOT"
        db CMD_SET_POSITION, #02, #02
        db CMD_SET_SCALE, #21
        db "CONSTRUCTION"
        db CMD_SET_SCALE, #00
        db CMD_SET_ATTRIBUTE, #45
        db CMD_SET_POSITION, #01, #15
        db "ELECTRONICS"
        db CMD_SET_POSITION, #04, #15
        db "NUCLEAR"
        db CMD_SET_POSITION, #07, #15
        db "PHASERS"
        db CMD_SET_POSITION, #0a, #15
        db "MISSILES"
        db CMD_SET_POSITION, #0d, #15
        db "CANNON"
        db CMD_SET_POSITION, #10, #15
        db "ANTI-GRAV"
        db CMD_SET_POSITION, #13, #15
        db "TRACKS"
        db CMD_SET_POSITION, #16, #15
        db "BIPOD"
        db CMD_SET_POSITION, #15, #05
        db "EXIT START"
        db CMD_NEXT_LINE
        db "MENU ROBOT"
        db CMD_SET_ATTRIBUTE, #43
        db CMD_SET_POSITION, #02, #16
        db "3"
        db CMD_SET_POSITION, #05, #16
        db "20"
        db CMD_SET_POSITION, #08, #16
        db "4"
        db CMD_SET_POSITION, #0b, #16
        db "4"
        db CMD_SET_POSITION, #0e, #16
        db "2"
        db CMD_SET_POSITION, #11, #16
        db "10"
        db CMD_SET_POSITION, #14, #16
        db "5"
        db CMD_SET_POSITION, #17, #16
        db "3"
        db CMD_SET_SCALE, #00
        db CMD_SET_ATTRIBUTE, #46
        db CMD_SET_POSITION, #06, #00
        db "-- RESOURCES --"
        db CMD_NEXT_LINE
        db "-- AVAILABLE --"
        db CMD_SET_ATTRIBUTE, #44
        db CMD_SET_POSITION, #09, #04
        db "GENERAL"
        db CMD_SET_POSITION, #0b, #00
        db "ELECTRONICS"
        db CMD_SET_POSITION, #0c, #04
        db "NUCLEAR"
        db CMD_NEXT_LINE
        db "PHASERS"
        db CMD_SET_POSITION, #0e, #03
        db "MISSILES"
        db CMD_SET_POSITION, #0f, #05
        db "CANNON"
        db CMD_SET_POSITION, #10, #04
        db "CHASSIS"
        db CMD_SET_POSITION, #12, #06
        db "TOTAL"
        db CMD_END
    ; Script end:
    ld (iy + ROBOT_STRUCT_DIRECTION), 4  ; Robot facing south-east initially
    ld (iy + ROBOT_STRUCT_ALTITUDE), 0

    ; Make a copy of the player resources:
    ld hl, Lfd22_player1_resource_counts
    ld de, Lfd29_resource_counts_buffer
    ld bc, 7
    ldir

    call Lcbe0_draw_resource_counts_in_construction_screen
    ld hl, 2
    ld (Lfd1f_cursor_position), hl  ; start in the second column, first piece ("bipod")
    xor a
    ld (Lfd21_construction_selected_pieces), a
    call Lcc1f_update_selected_pieces_and_robot_preview
    ld c, COLOR_YELLOW + COLOR_BRIGHT
    call Lcba9_construction_screen_set_option_color
Lca0f_waiting_for_key_press_loop:
    call Ld37c_read_keyboard_joystick_input
    and #1f
    ; some key has been pressed:
    jr z, Lca0f_waiting_for_key_press_loop
    ld hl, (Lfd1f_cursor_position)
    ld a, (Lfd0c_keyboard_state)
    and #10
    jp z, Lcb00_construction_screen_move  ; Moving through the options (no space pressed)
    ; "fire" has been pressed:
    ld a, l  ; which column is the cursor in:
    or a
    jp z, Lcb8e_construction_screen_exit  ; "fire" pressed on "exit menu" (column 0)
    dec a
    jp z, Lcb52_construction_screen_start_robot  ; "fire" pressed on "start robot" (column 1)
    ; "fire" pressed on a piece:
    ld a, h  ; a = selected piece
    ld e, a  ; potential optimization: no need for the ld a, h; just ld e, a; ld b, e
    ld b, a
    inc b
    xor a
    scf
    ; get the selected piece as a one-hot representation (one bit on, all others off):
Lca30_piece_to_one_hot_loop:
    rla
    djnz Lca30_piece_to_one_hot_loop
    ld d, a
    ld a, (Lfd21_construction_selected_pieces)
    ld c, a
    and d  ; check if we already had that piece:
    jr nz, Lcaa4_construction_remove_piece
    ld a, e  ; e has the new selected piece
    cp 3
    jr nc, Lca57_construction_add_piece  ; If it's not a chassis piece, just add it
    ; It's a chassis piece, check if we already had one selected:
    ld a, c  ; c still has the currently selected pieces in the robot
    and 7
    jr z, Lca57_construction_add_piece
    ; Replace chassis piece:
    push de
        ld e, 255
        ; Here a = still has the currently selected pieces in the robot
        ; This loop gets in "e" the index of the currently selected chassis in the robot:        
Lca48_get_current_chassis_loop:
        inc e
        rrca
        jr nc, Lca48_get_current_chassis_loop
        call Lcac1_update_resources_buffer_when_removing_a_piece
        ; We remove the current chassis from the robot:
        ld a, c
        and #f8
        ld c, a
        ld (Lfd21_construction_selected_pieces), a
    pop de
Lca57_construction_add_piece:
    ld a, c  ; c still has the currently selected pieces in the robot
    or d  ; we add in the new piece
    and #78
    cp #78
    jp z, Lcaac_construction_beep_and_back_to_loop
    ; Update the resources:
    ld hl, Lcaf0_piece_costs
    ld a, e
    call Ld351_add_hl_a
    ld b, (hl)  ; b has the piece cost
    ld hl, Lcaf8_piece_factory_type
    ld a, e
    call Ld351_add_hl_a
    ld a, (hl)  ; a has the index of the resource to subtract from
    ld hl, Lfd29_resource_counts_buffer
    call Ld351_add_hl_a
    ld a, (hl)
    sub b
    jp nc, Lca89_construction_add_piece_continue  ; If we had enough, we are good
    neg
    ld b, a
    ld a, (Lfd29_resource_counts_buffer)
    sub b
    jp c, Lcaac_construction_beep_and_back_to_loop
    ld (Lfd29_resource_counts_buffer), a
    xor a
Lca89_construction_add_piece_continue:
    ld (hl), a  ; update the resource counts after subtracting the piece cost
    ld a, c
    or d
    ld (Lfd21_construction_selected_pieces), a  ; update the robot pieces
    ld a, 100
    call Lccac_beep  ; Potential optimization: the following lines are identical to the end of the 
                     ; function below, unify.
    call Lcc1f_update_selected_pieces_and_robot_preview
    call Lcbe0_draw_resource_counts_in_construction_screen
Lca9a_wait_for_fire_button_release:
    call Ld37c_read_keyboard_joystick_input
    and 16
    jr nz, Lca9a_wait_for_fire_button_release
    jp Lcb4a_pause_and_back_to_construction_loop


; --------------------------------
; Removes a piece from the current robot we are editing
; Input:
; - e: piece to remove
Lcaa4_construction_remove_piece:
    call Lcac1_update_resources_buffer_when_removing_a_piece
    ld a, c
    xor d
    ld (Lfd21_construction_selected_pieces), a
Lcaac_construction_beep_and_back_to_loop:
    ld a, 120
    call Lccac_beep
    call Lcc1f_update_selected_pieces_and_robot_preview
    call Lcbe0_draw_resource_counts_in_construction_screen
Lcab7_wait_for_fire_button_release:
    call Ld37c_read_keyboard_joystick_input
    and 16
    jr nz, Lcab7_wait_for_fire_button_release
    jp Lcb4a_pause_and_back_to_construction_loop


; --------------------------------
; Update the resource counts buffer in the construction screen after removing a piece from the 
; robot.
; Input:
; - e: piece to remove
Lcac1_update_resources_buffer_when_removing_a_piece:
    ld hl, Lcaf0_piece_costs
    ld a, e
    call Ld351_add_hl_a
    ld b, (hl)  ; get the cost of the piece.
    ld hl, Lcaf8_piece_factory_type
    ld a, e
    call Ld351_add_hl_a
    ld a, (hl)  ; Get the index in the resource counts that we should add it to.
    ld hl, Lfd29_resource_counts_buffer
    call Ld351_add_hl_a
    ld a, (hl)
    add a, b  ; Add the piece cost to the corresponding resource counts.
    ld (hl), a
    ; See if we have added more than the player had:
    push hl
        ld a, l
        sub 7  ; The actual player resource counts (Lfd22_player1_resource_counts) are just 7 bytes 
               ; offset from the buffer.
        ld l, a
        ld b, (hl)  ; Get the current resources that the player has on the index we just added to.
    pop hl
    ld a, (hl)
    cp b
    ret z  ; If after adding the piece cost, we still haven't reached the resources the player had 
           ; originally in that index, we are done.
    ret c
    ; Otherwise, we need to cap the resource count in this index to what the player had, and add 
    ; the rest to the general resources index (0):
    ld (hl), b
    sub b
    ld b, a
    ld a, (Lfd29_resource_counts_buffer)
    add a, b
    ld (Lfd29_resource_counts_buffer), a
    ret


; --------------------------------
; How much does each piece cost: bipod, tracks, anti-grav, cannon, missiles, phasers, nuclear, 
; electronics:
Lcaf0_piece_costs:
    db 3, 5, 10, 2, 4, 4, 20, 3

; Which factory type produces resources for each piece:
; - bipod, tracks, anti-grav are all produced in the "chassis" factory types (6), whereas the other 
;   pieces.
;   have dedicated factories for themselves.
Lcaf8_piece_factory_type:
    db 6, 6, 6, 5, 4, 3, 2, 1


; --------------------------------
; Moves the cursor around the construction screen after pressing one of the direction keys
; Input:
; - h: cursor row (selected piece if column == 2)
; - l: cursor column
Lcb00_construction_screen_move:
    ld a, (Lfd0c_keyboard_state)
    and 3
    jr z, Lcb1b_construction_screen_move_up_down
    ld c, a
    ld a, l
    rr c
    jr nc, Lcb0e_right_not_pressed
    inc a
Lcb0e_right_not_pressed:
    rr c
    jr nc, Lcb13_left_not_pressed
    dec a
Lcb13_left_not_pressed:
    cp 3  ; make sure we did not move out of bounds
    jr nc, Lcb4a_pause_and_back_to_construction_loop
    ld l, a  ; l = new cursor column
    jp Lcb36_construction_screen_update_color_of_selected_option_after_move

Lcb1b_construction_screen_move_up_down:
    ld a, (Lfd0c_keyboard_state)
    ; Rotate the keyboard state to get to the bits representing up/down
    rrca
    rrca
    ld c, a
    ld a, l
    cp 2  ; If we are not on the pieces column, just return as we cannot move up/down:
    jr nz, Lcb4a_pause_and_back_to_construction_loop
    ld a, h
    rr c
    jr nc, Lcb2c_up_not_pressed
    dec a  ; move up
Lcb2c_up_not_pressed:
    rr c
    jr nc, Lcb31_down_not_pressed
    inc a  ; move down
Lcb31_down_not_pressed:
    cp 8  ; make sure we did not move out of bounds
    jr nc, Lcb4a_pause_and_back_to_construction_loop
    ld h, a  ; h = new cursor row
Lcb36_construction_screen_update_color_of_selected_option_after_move:
    push hl
        ld c, COLOR_CYAN + COLOR_BRIGHT
        call Lcba9_construction_screen_set_option_color
    pop hl
    ld (Lfd1f_cursor_position), hl
    ld c, COLOR_YELLOW + COLOR_BRIGHT
    call Lcba9_construction_screen_set_option_color
    ld a, 20
    call Lccac_beep

Lcb4a_pause_and_back_to_construction_loop:
    ld b, 10
Lcb4c_pause_loop:
    halt
    djnz Lcb4c_pause_loop
    jp Lca0f_waiting_for_key_press_loop


; --------------------------------
Lcb52_construction_screen_start_robot:
    ld a, (Lfd21_construction_selected_pieces)
    ld c, a
    and 7
    jr z, Lcb4a_pause_and_back_to_construction_loop  ; If we have not selected any piece, do not 
                                                     ; allow the robot to start
    ld a, c
    and #78
    jr z, Lcb4a_pause_and_back_to_construction_loop  ; If we have not selected any weapon, do not 
                                                     ; allow the robot to start
    ld hl, Lfd29_resource_counts_buffer
    ld de, Lfd22_player1_resource_counts
    ld bc, 7
    ldir  ; copy the resource buffer (that has the price of the robot discounted) to the player 
          ; resources
    ld hl, (Lfd0e_player_x)
    ld a, (Lfd0d_player_y)
    add a, 4
    ld b, a  ; robot starts 4 positions off the player in the y axis to be placed at the entrance 
             ; of the factory
    ld (iy + ROBOT_STRUCT_CONTROL), ROBOT_CONTROL_AUTO
    call Lcc7c_set_robot_position
    ld a, (Lfd21_construction_selected_pieces)
    ld (iy + ROBOT_STRUCT_PIECES), a
    ; Make the sound corresponding to having created a robot:
    ld b, 80
Lcb82_sound_loop:
    ld a, b
    call Lccac_beep
    ld a, b
    sub 5
    ld b, a
    cp 20
    jr nc, Lcb82_sound_loop
    ; And then just exit the construction screen:
    ; jp Lcb8e_construction_screen_exit


; --------------------------------
Lcb8e_construction_screen_exit:
    ld a, 200
    call Lccac_beep  ; make a sound
    ld a, 5
    ld (Lfd30_player_elevate_timer), a  ; make the player levitate a bit after exiting
    push iy
        call Lcffe_clear_5b00_buffer  ; clear the screen buffer
        call Ld0ca_draw_in_game_screen_and_hud
    pop iy
    ; Restore the in-game interrupt (which was deactivated in the construction screen):
    ld hl, Ld566_interrupt
    ld (Lfdfe_interrupt_pointer), hl
    ret


; --------------------------------
; input:
; - (Lfd1f_cursor_position): option to change the color
; - c: color to set
Lcba9_construction_screen_set_option_color:
    ld hl, (Lfd1f_cursor_position)
    ld a, l
    cp 2  ; if cursor is in column "2' (the piece names)
    jr z, Lcbc6_set_attribute_piece_name
    add a, a
    add a, l
    add a, a
    add a, 164
    ld l, a  ; l = a*6 + 5*32 + 4  
    ld h, #5a  ; Here, if a == 0, we will change the color of the "EXIT MENU" option, and if a == 
               ; 1, of the "START ROBOT" option.
    ld b, 5
    call Lcbdb_set_attribute_loop  ; change color of the first line
    ld a, l
    add a, 27
    ld l, a
    ld b, 5
    jr Lcbdb_set_attribute_loop  ; change color of the second line

Lcbc6_set_attribute_piece_name:
    ; Calculate the position of the "h"-th piece name and paint it with color "c"
    ld a, h
    add a, a
    add a, h  ; a = h*3
    neg  ; a = -h*3
    add a, 22  ; a = 22 - h*3
    add a, a
    add a, a
    add a, a  ; a = 8*(22 - h*3)
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl  ; hl = 32 * (22 - h*3)
    ld de, L5800_VIDEOMEM_ATTRIBUTES + 21
    add hl, de  ; hl = L5800_VIDEOMEM_ATTRIBUTES + 21 + 32 * (22 - h*3)
    ; set the attribute for 11 characters in a row (which is the length of the larger piece name 
    ; "electronics"):
    ld b, 11
    ; set "b" positions in the attribute table to attribute "c":
Lcbdb_set_attribute_loop:
    ld (hl), c
    inc hl
    djnz Lcbdb_set_attribute_loop
    ret


; --------------------------------
Lcbe0_draw_resource_counts_in_construction_screen:
    ld de, Lfd29_resource_counts_buffer
    ld hl, 0  ; hl will accumulate total resources
    ld c, 9  ; start y coordinate to draw resource counts
    ld b, 7
Lcbea:
    ld a, (de)
    call Ld351_add_hl_a
    ld a, (de)
    call Lcc08_draw_single_resource_count_in_construction_screen
    inc de
    inc c
    ld a, b
    cp 7
    jr nz, Lcbfa
    inc c  ; the fist time, we leave a blank space between general resources and the rest
Lcbfa:
    djnz Lcbea
    call Ld42d_execute_ui_script
    ; script start:
        db CMD_SET_POSITION, #12, #0c
        db CMD_END
    ; script end:
    ld e, ' '
    jp Ld401_render_16bit_number_3digits  ; render the sum of all resources


; --------------------------------
Lcc08_draw_single_resource_count_in_construction_screen:
    push af
        ld a, c
        ld (Lcc11_selfmodifying), a  ; set the desired y coordinate
        call Ld42d_execute_ui_script
        ; script start:
            db CMD_SET_POSITION
Lcc11_selfmodifying:
            db #00, #0d
            db CMD_END
        ; script end:
    pop af
    push bc
    push de
    push hl
        call Ld3e5_render_8bit_number
    pop hl
    pop de
    pop bc
    ret


; --------------------------------
; - Paints the selected pieces in white
; - those not selected in yellow
; - synthesizes the robot preview and draws it to screen
; input:
; - iy: robot struct pointer
Lcc1f_update_selected_pieces_and_robot_preview
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + 16
    ld a, (Lfd21_construction_selected_pieces)
    ld c, a
    ld b, 8  ; 8 pieces
    ; paint the selected pieces in white color, and non-selected in yellow:
Lcc28_loop_piece:
    ld e, COLOR_YELLOW
    rl c
    jr nc, Lcc30
    ld e, COLOR_BRIGHT + COLOR_WHITE
Lcc30:
    push bc
        ld bc, #0403
Lcc34_loop_y:
        push bc
Lcc35_loop_x:
            ld (hl), e
            inc hl
            djnz Lcc35_loop_x
            ld a, 28  ; next line
            call Ld351_add_hl_a
        pop bc
        dec c
        jr nz, Lcc34_loop_y
    pop bc
    djnz Lcc28_loop_piece

    call Lcffe_clear_5b00_buffer
    ld a, (Lfd21_construction_selected_pieces)
    ld (iy + ROBOT_STRUCT_PIECES), a
    ld de, #0a07  ; isometric coordinates of the robot, so it shows up in the right place in the 
                  ; screen.
    call Lcee8_draw_robot_to_buffer
    ld a, (Lcf3f_selfmodifying_sprite_elevation)
    ld (iy + ROBOT_STRUCT_HEIGHT), a
    ; Copies a block of 32*48 pixels from #6168 to (0,120) in video memory: this is the preview of 
    ; the robot being constructed.
    ld bc, #0448
    ld de, #6168
    ld hl, L4000_VIDEOMEM_PATTERNS + #08e0  ; (x, y) = (0, 120)
Lcc63_loop_y:
    push bc
        push hl
Lcc65_loop_x:
            ld a, (de)
            ld (hl), a
            inc de
            inc hl
            djnz Lcc65_loop_x
            ld a, e
            add a, 16
            ld e, a
            ld a, d
            adc a, 0
            ld d, a
        pop hl
        call Ld32a_inc_video_ptr_y_hl
    pop bc
    dec c
    jr nz, Lcc63_loop_y
    ret


; --------------------------------
; Input:
; - hl: x coordinate
; - b: y coordinate
Lcc7c_set_robot_position:
    ld (iy + ROBOT_STRUCT_X), l
    ld (iy + ROBOT_STRUCT_X + 1), h
    ld (iy + ROBOT_STRUCT_Y), b
    push hl
        ld a, b
        call Lcca6_compute_map_ptr
        ld (iy + ROBOT_STRUCT_MAP_PTR), l
        ld (iy + ROBOT_STRUCT_MAP_PTR + 1), h
        set 6, (hl)
    pop hl
    ld c, (iy + ROBOT_STRUCT_Y)
    ld a, (iy + ROBOT_STRUCT_CONTROL)
    rlca
    and 1
    ld b, a  ; b = 0 if player robot, and b = 1 if enemy robot.
    jp Ld65a_flip_2x2_radar_area


; --------------------------------
; Computes the pointer in the map corresponding to the current x, y coordinates of the player.
Lcca0_compute_player_map_ptr:
    ld hl, (Lfd0e_player_x)
    ld a, (Lfd0d_player_y)
    ; jp Lcca6_compute_map_ptr


; --------------------------------
; Computes the pointer in the map corresponding to some x, y coordinates.
; Input:
; - hl: x
; - a: y
; Output:
; - hl: map ptr
Lcca6_compute_map_ptr:
    add a, a
    add a, #dd
    add a, h
    ld h, a  ; h += a*2 + #dd
    ret


; --------------------------------
; Produces a beep sound.
; input:
; - a: sound period (lower means higher pitch)
Lccac_beep:
    push bc
        ld b, a
        xor a
        ld c, a
Lccb0_beep_outer_loop:
        push bc
            xor 16
            out (ULA_PORT), a  ; change MIC/EAR state (to produce sound)
Lccb5_inner_loop:
            djnz Lccb5_inner_loop
        pop bc
        dec c
        jr nz, Lccb0_beep_outer_loop
    pop bc
    ret


; --------------------------------
; Clears the double buffer, draws the game area there, and copies it to the video memory.
Lccbd_redraw_game_area:
    call Lcfd7_draw_blank_map_in_buffer
    call Lccc6_draw_map_to_buffer
    jp Ld071_copy_game_area_buffer_to_screen


; --------------------------------
; Renders the player and the map to the buffer
Lccc6_draw_map_to_buffer:
    ld hl, 0
    ld (Lfd11_player_iso_coordinates_if_deferred), hl  ; mark that the player rendering is not 
                                                       ; deferred.
    ; Draw the player shadow:
    xor a
    ld (Lcf3f_selfmodifying_sprite_elevation), a
    ld hl, (Lfd0e_player_x)
    ld de, (Lfd06_scroll_ptr)
    ld a, d
    and #01
    ld d, a  ; keep only the lower 9 bits of (Lfd06_scroll_ptr), which contain the x coordinate
    xor a
    sbc hl, de  ; hl = player_x - scroll_x
    ld e, l
    ld a, (Lfd0d_player_y)
    ld d, a
    ld a, 1  ; draw graphic 1 (player shadow)
    call Lcf2d_draw_sprite_to_buffer

    ld hl, (Lfd06_scroll_ptr)
    ld a, 32
    call Ld351_add_hl_a
    ld de, 32
    ; Draw the visible part of the map:
    ; - "de" starts at 32 and decrements at each loop, and keeps track of the visible area we need 
    ;   to draw.
Lccf3_outer_loop:
    dec hl
    dec e
    push hl
    push de
        ; Each inner iteration represents a diagonal row of the map (horizontal when projected to 
        ; the screen).
        ; - So, if a row starts in (7,0), it will draw: (7,0), (8,1), (9,2), etc.
        ; - In the first iteration, it'll draw the objects that appear in the top of the screen.
        ; - In subsequent iterations it goes down one row every time. 
        ; - In the first iteration of the outer loop "e" will go from 31 -> 32, then from 30 -> 32, 
        ;   29 -> 32, etc.
        ; - until we reach 15 -> 31, 14 -> 30, etc. as at most the inner loop loops 16 times (
        ;   controlled by "d").
        ; - This is to capture the visible part of the screen with the isometric projection.
Lccf7_inner_loop:
        ld a, e
        or a
        jp m, Lcd01_not_visible  ; if we are outside of the visible area, skip
        ld a, (hl)
        or a
        call nz, Lcd18_draw_map_cell  ; If there is anything in the map, draw it!
Lcd01_not_visible:
        ; move to the next position of the map to draw:
        inc h  ; This does "y++" (since each row is 512 bytes long)
        inc h
        inc hl ; This does "x++". Potential optimization: "inc l"?
        inc d  ; keep track of how many positions we have drawn in this outer loop iteration
        inc e
        ld a, d
        cp 16
        jr nc, Lcd10_exit_inner_loop  ; If we have done 16 iterations of the inner loop, end
        ld a, e
        cp 32  ; if we have reached the limit visible in the screen, we are done.
        jr nz, Lccf7_inner_loop
Lcd10_exit_inner_loop:
        ld a, e
    pop de
    pop hl
    cp 1  ; when after drawing one row, "e == 1", end, which means there is no chance of anything 
          ; visible any more in subsequent outer loop iterations.
    jr nz, Lccf3_outer_loop
    ret


; --------------------------------
; Draws whatever is in this map cell: map elements, robots, player, etc.
; Input:
; - hl: map ptr
Lcd18_draw_map_cell:
    ; Start by drawing the map element in this position, if any:
    push hl
    push de
    push af
        bit 5, a  ; Map elements occupy a 2x2 block in the map, but only the bottom-left corner has 
                  ; bit 5 == 0.
        jr nz, Lcd2b_skip_map_element_draw
        and #1f  ; If there is no map element in this position, skip.
        jr z, Lcd2b_skip_map_element_draw
        ld hl, Lcf3f_selfmodifying_sprite_elevation
        ld (hl), 0
        call Lcf2d_draw_sprite_to_buffer
Lcd2b_skip_map_element_draw:
    pop af
    pop de
    pop hl
    ; Now check if there is an object here (robot, etc.):
    bit 6, a  ; objects are marked with bit 6
    call nz, Lce12_draw_object_to_map
    ld a, (hl)
    bit 7, a  ; the player is marked with bit 7
    ret z  ; player is not here
    ; Draw the player:
    ld bc, (Lfd11_player_iso_coordinates_if_deferred)
    ld a, b
    or c
    jr nz, Lcd79_player_rendering_was_deferred  ; player rendering was already deferred.
    ; Check if there is a map element that would occlude the player sprite when it shouldn't,
    ; and defer player rendering if so:
    push de
        ; "de" will have the map pointer where the player should be rendered at.
        ; It should be == "hl" if not deferred.
        ld d, h
        ld e, l
        call Lcd96_find_near_in_front_map_element
        push hl
            dec hl
            dec h
            dec h
            call Lcd90_find_near_in_front_map_element
            inc h
            inc h
            call Lcd90_find_near_in_front_map_element
            inc h
            inc h
            ld a, h
            cp #fd
            jr nc, Lcd63_out_of_map_bounds
            call Lcd90_find_near_in_front_map_element
            inc hl
            call Lcd90_find_near_in_front_map_element
            inc hl
            call Lcd90_find_near_in_front_map_element
Lcd63_out_of_map_bounds:
        pop hl
        ld a, d
        cp h
        jr nz, Lcd6f_defer_player_rendering
        ld a, e
        cp l
        jr nz, Lcd6f_defer_player_rendering
    pop de
    jr Lcd81_render_player_push
Lcd6f_defer_player_rendering:
        ex de, hl
        set 7, (hl)  ; mark the player as being in the deferred coordinates.
        ex de, hl
    pop de
    ld (Lfd11_player_iso_coordinates_if_deferred), de
    ret

Lcd79_player_rendering_was_deferred:
    res 7, (hl)  ; remove the player mark from the deferred position
    push hl
    push de
        ld d, b
        ld e, c  ; set the correct isometric coordinates (before it was deferred).
        jr Lcd83_render_player

Lcd81_render_player_push:
    push hl
    push de
Lcd83_render_player:
        ld a, (Lfd10_player_altitude)
        ld (Lcf3f_selfmodifying_sprite_elevation), a
        xor a
        call Lcf2d_draw_sprite_to_buffer
    pop de
    pop hl
    ret


; --------------------------------
; Sees if there is a map element that would be rendered on top of the object in "hl", and
; returns its map pointer in de
; Input:
; - hl: map ptr to check
; - de: map ptr to update if we find a "more in front" map element
Lcd90_find_near_in_front_map_element:
    bit 6, (hl)
    ret z
    call Lcdbf_update_de_if_hl_more_in_front_internal
Lcd96_find_near_in_front_map_element:
    push hl
        dec hl  ; x -= 1
        inc h  ; y += 1
        inc h
        ld a, h
        cp #fd  ; check if pointer is outside of map bounds
        jr nc, Lcda7_skip_first_row  ; out of bounds
        call Lcdb8_update_de_if_hl_more_in_front
        inc hl  ; x += 1
        call Lcdb8_update_de_if_hl_more_in_front
        dec hl  ; x -= 1
Lcda7_skip_first_row:
        dec h
        dec h  ; y -= 1
        call Lcdb8_update_de_if_hl_more_in_front
        inc hl  ; x += 1
        inc hl  ; x += 1
        inc h  ; y += 1
        inc h
        ld a, h
        cp #fd  ; check if pointer is outside of map bounds
        call c, Lcdb8_update_de_if_hl_more_in_front
    pop hl
    ret


; --------------------------------
; Checks if there is a map element in "hl" that is "in front" (rendered lower in the screen) of the
; position pointed to by "de", and if so, overwrites "de" with "hl".
; Input:
; - hl: map ptr to check
; - de: map ptr to update if we find a "more in front" map element
Lcdb8_update_de_if_hl_more_in_front:
    bit 5, (hl)
    ret nz  ; return if this is not the bottom-left corner of the a map object
    ld a, (hl)
    and #1f
    ret z  ; return if there is nothing in this map position
    ; If we are here is that we are in a map position with the bottom-left corner of a map element.
Lcdbf_update_de_if_hl_more_in_front_internal:
    ld a, e
    sub l
    ld c, a  ; c = e - l  (difference in x, ignoring highest bit)
    ld a, d
    sub #dd
    srl a
    ld b, a  ; b = (d - #dd) / 2
    ld a, h
    sub #dd
    srl a  ; a = (h - #dd) / 2
    sub b  ; a = ((h - #dd) / 2) - ((d - #dd) / 2)  (difference in y)
    add a, c  ; "a" has (hl.y - de.y) + (de.x - hl.x)
    ret m  ; return if whatever is in "de" is rendered "lower on the screen" when projected, 
    jr nz, Lcdd5
    ld a, c  ; c still contains e - l (difference in x)
    or a
    ret p  ; return if whatever is in de has a higher x coordinate.
Lcdd5:
    ld d, h
    ld e, l
    ret


; --------------------------------
; Finds if there is a robot with the same map pointer as hl, and returns it in "iy".
; Input:
; - hl: map ptr
; Output:
; - iy: robot ptr
; - z: robot found
; - nz: no robot found
Lcdd8_get_robot_at_ptr:
    ld iy, Lda00_player1_robots
    ld b, MAX_ROBOTS_PER_PLAYER*2
Lcdde_get_robot_below_player_loop:
    ld a, (iy + ROBOT_STRUCT_MAP_PTR)
    cp l
    jr nz, Lcde9_next_robot
    ld a, (iy + ROBOT_STRUCT_MAP_PTR + 1)
    cp h
    ret z
Lcde9_next_robot:
    push de
        ld de, ROBOT_STRUCT_SIZE
        add iy, de
    pop de
    djnz Lcdde_get_robot_below_player_loop
    or 1
    ret


; --------------------------------
; Find decoration at map pointer hl
; Input:
; - hl: map pointer to find a decoration for.
; Returns:
; - iy: ptr to a decoration that has "hl" as the map pointer (if found)
; - z: decoration found.
; - nz: decoration not found.
Lcdf5_find_building_decoration_with_ptr:
    ld iy, Lff01_building_decorations
    ld b, 56
Lcdfb_loop:
    ld a, (iy + BULLET_STRUCT_MAP_PTR)
    cp l
    jr nz, Lce06_skip
    ld a, (iy + BULLET_STRUCT_MAP_PTR + 1)
    cp h
    ret z
Lce06_skip:
    push de
        ld de, 3
        add iy, de
    pop de
    djnz Lcdfb_loop
    or 1
    ret


; --------------------------------
; See if there is an object (robot, decoration, bullet) with map ptr equal to "hl" and draws it.
; Input:
; - hl: map ptr
; - de: isometric coordinates
Lce12_draw_object_to_map:
    call Lcdd8_get_robot_at_ptr
    jr z, Lce68_draw_robot_or_bullet  ; if there is a robot, draw it
    call Lcdf5_find_building_decoration_with_ptr
    jr z, Lce38_draw_decoration  ; if there is a decoration, draw it
    ld iy, Ld7d3_bullets
    ld b, MAX_BULLETS
Lce22_loop_bullet:
    ld a, (iy + BULLET_STRUCT_MAP_PTR)
    cp l
    jr nz, Lce2e_next_bullet
    ld a, (iy + BULLET_STRUCT_MAP_PTR + 1)
    cp h
    jr z, Lce68_draw_robot_or_bullet  ; if there is a bullet, draw it
Lce2e_next_bullet:
    push de
        ld de, BULLET_STRUCT_SIZE
        add iy, de
    pop de
    djnz Lce22_loop_bullet
    ret


; --------------------------------
; Draws a decoration to the map (a flag, the "H" in a warbase, pieces on top of factories.)
; Input:
; - iy: decoration ptr
; - de: isometric coordinates
Lce38_draw_decoration:
    push hl
    push de
        ld a, (iy + BUILDING_DECORATION_STRUCT_TYPE)
        ld c, a
        ld hl, Lce5f_decoration_drawing_elevations
        call Ld351_add_hl_a
        ld a, (hl)
        ld (Lcf3f_selfmodifying_sprite_elevation), a
        ld a, c
        ld hl, Lce56_decoration_sprite_indexes
        call Ld351_add_hl_a
        ld a, (hl)
        call Lcf2d_draw_sprite_to_buffer
    pop de
    pop hl
    ret

Lce56_decoration_sprite_indexes:
    db #2c, #28, #25, #23, #20, #1d, #17, #2a, #2b
Lce5f_decoration_drawing_elevations:
    db #13, #0f, #0f, #0f, #0f, #0f, #0f, #1a, #1a


; --------------------------------
; Draws a bullet to the map.
; Input:
; - iy: bullet/robot struct ptr.
; - hl: map ptr.
; - d, e: isometric coordinates.
Lce68_draw_robot_or_bullet:
    push de
        ld d, h
        ld e, l
        call Lcd96_find_near_in_front_map_element
        ; if "de" is different from "hl", update the ptr of the bullet/robot instead of drawing it:
        ; This is because it could be that the object in "de" would overwrite the bottom of the 
        ; object in "hl". So, we are just "deferring" the rendering.
        ld a, d
        cp h
        jr nz, Lce76_update_robot_bullet_ptr  ; defer rendering
        ld a, e
        cp l
        jr z, Lce82_draw_robot_or_bullet_continue  ; if we only differ in "x" form the potential
                                                   ; occluder, continue
Lce76_update_robot_bullet_ptr:
        ; Defer rendering to later, after we have drawn the map element in "de":
        ex de, hl
            set 6, (hl)
            ld (iy + BULLET_STRUCT_MAP_PTR), l
            ld (iy + BULLET_STRUCT_MAP_PTR + 1), h
        ex de, hl
    pop de
    ret

Lce82_draw_robot_or_bullet_continue:
    pop de  ; pop "de", which was pushed when we jumped here (isometric coordinates)
    push de
        ex de, hl  ; de = original map ptr.
        ld l, (iy + ROBOT_STRUCT_X)
        ld h, (iy + ROBOT_STRUCT_X + 1)
        ld a, (iy + ROBOT_STRUCT_Y)
        call Lcca6_compute_map_ptr  ; recompute map ptr in "hl" from the x, y coordinates in "hl", 
                                    ; "a".
        ; If the "Lcd96_find_near_in_front_map_element" call above found an object that will be 
        ; drawn later and would occlude this one, do not draw yet:
        ld a, d
        cp h
        jr nz, Lce9c_object_was_deferred  ; This means that the object was deferred for rendering 
                                          ; earlier, so, we draw it now.
        ld a, e
        cp l
        jr nz, Lce9c_object_was_deferred  ; This means that the object was deferred for rendering 
                                          ; earlier, so, we draw it now.
    pop de
    jr Lcec3_draw_robot_or_bullet_internal
Lce9c_object_was_deferred:
        ; Reestablish the pointer of the object to its original value:
        ld (iy + ROBOT_STRUCT_MAP_PTR), l
        ld (iy + ROBOT_STRUCT_MAP_PTR + 1), h
        ld b, h
        ld c, l
        ex de, hl
    pop de
    push de
    push hl
        res 6, (hl)  ; remove the object from its deferred position
        dec hl
        dec e
        ; Adjust the isometric coordinates to account for the fact that the object was moved to 
        ; defer its rendering.
Lceac_loop_x:
        ld a, c
        cp l
        jr z, Lceb4_loop_y
        inc hl
        inc e
        jr Lceac_loop_x
Lceb4_loop_y:
        ld a, b
        cp h
        jr z, Lcebd_loop_exit
        dec h
        dec h
        dec d
        jr Lceb4_loop_y
Lcebd_loop_exit:
        call Lcec3_draw_robot_or_bullet_internal
    pop hl
    pop de
    ret


; --------------------------------
; Draws the sprites corresponding to a bullet or robot to the double buffer.
; Input:
; - iy: robot/bullet ptr.
Lcec3_draw_robot_or_bullet_internal:
    push iy
    pop bc
    ld a, b  ; Potential optimization: push/pop not needed, just "la a,iyh"
    cp #d8  ; bullets have pointers < #d800, if its bigger, it's a robot.
    jp nc, Lcee8_draw_robot_to_buffer
    ; Draw the bullet
    push hl
    push de
        ld c, (iy + BULLET_STRUCT_TYPE)
        ld a, (iy + BULLET_STRUCT_DIRECTION)
        ; get the sprite # of the bullet:
        cp 3
        ccf
        rl c
        ld a, (iy + BULLET_STRUCT_ALTITUDE)
        ld (Lcf3f_selfmodifying_sprite_elevation), a
        ; get the sprite # of the bullet (continued):
        ld a, 43
        add a, c
        call Lcf2d_draw_sprite_to_buffer
    pop de
    pop hl
    ret


; --------------------------------
; Input:
; - de: isometric coordinates
; - iy: pointer to the robot struct
Lcee8_draw_robot_to_buffer:
    push hl
        ld c, (iy + ROBOT_STRUCT_PIECES)  ; which pieces are selected for the robot (1 bit per 
                                          ; piece).
        ld b, 8  ; up to 8 different pieces
        ld a, (iy + ROBOT_STRUCT_ALTITUDE)
        ld (Lcf3f_selfmodifying_sprite_elevation), a
Lcef4_piece_loop:
        rr c
        call c, Lcefd_draw_robot_piece_to_buffer  ; if the piece is selected, draw it.
        djnz Lcef4_piece_loop
    pop hl
    ret


; --------------------------------
; Input:
; - b: 8 - piece to draw
; - de: isometric coordinates
; - iy: robot ptr.
Lcefd_draw_robot_piece_to_buffer:
    push bc
    push de
        ld a, 8
        sub b  ; a = piece to draw (0 = bipod, 1 = tracks, etc.)
        push af
            ld c, (iy + ROBOT_STRUCT_DIRECTION)  ; one-hot representation of the robot direction
            ld b, 255  ; b will contain the direction (south-east, south-west, etc.)
Lcf08_direction_loop:
            inc b
            rr c
            jr nc, Lcf08_direction_loop
            add a, a
            add a, a
            add a, b  ; a now contains the offset in the graphic indices table of the piece graphic 
                      ; to draw.
            ld hl, Ld6c8_piece_direction_graphic_indices
            call Ld351_add_hl_a
            ld a, (hl)  ; a now contains the index of the piece graphic to draw in the graphics 
                        ; table.
            add a, 22  ; + 22, since this will be later multiplied by 2, and is to skip the first 
                       ; 44 graphics in the "Ld6e8_additional_isometric_graphic_pointers" table.
            call Lcf2d_draw_sprite_to_buffer
        pop af
    pop de
    pop bc
    ld hl, Ld7b4_piece_heights
    call Ld351_add_hl_a  ; get piece height
    ld a, (Lcf3f_selfmodifying_sprite_elevation)
    add a, (hl)
    ld (Lcf3f_selfmodifying_sprite_elevation), a
    ret


; --------------------------------
; input:
; - a: index of the graphic to draw from Ld6e8_additional_isometric_graphic_pointers (divided by 2)
; - d, e: isometric coordinates.
Lcf2d_draw_sprite_to_buffer:
    ld c, a  ; we save the graphic to draw in c
    ; calculate the screen x coordinate:
    rlc e
    ld a, e
    add a, d
    sub 24
    ld l, a  ; l (x coordinate in nibbles) = e*2 + d - 24
    ; calculate the screen y coordinate:
    rlc e
    ld a, d
    add a, a
    add a, a
    add a, a
    add a, 100
    sub e
Lcf3f_selfmodifying_sprite_elevation: equ $ + 1
    sub 0  ; a = d*8+100 - e*4 - (Lcf3f_selfmodifying_sprite_elevation)  ; mdl:self-modifying
    ld h, a  ; h: y coordinate to draw to in pixels (starting from the bottom of the sprite)
    ld a, c  ; restore the graphic to draw
    and #3f
    ; here l = x coordinate in nibbles
    sra l  ; we push the least significant bit to the carry (now l is x coordinate in bytes)
    ; Here we have the coordinates where to draw:
    ; - l: x coordinate in bytes
    ; - h: y coordinate in pixels
    adc a, a  ; The carry is now added to the index, since each odd sprite is already
              ; pre-calculated with a 4 pixel offset in the x axis.
    push hl
        ld hl, Ld6e8_additional_isometric_graphic_pointers
        call Ld348_get_ptr_from_table
        ld c, (hl)  ; height in pixels
        inc hl
        ld b, (hl)  ; width in bytes
        inc hl
        ex de, hl  ; de: pointer to the actual graphic data
    pop hl
    xor a
    ld (Lcfaf_selfmodifying_left_pixel_skip), a  ; do not skip pixels from the left by default
    ld a, l
    cp 20
    ret p  ; if we are drawing beyond the buffer right edge, we are done
    ld a, h
    cp 160
    jr c, Lcf77_clip_sprite_left
    cp 226
    ret nc  ; if we are drawing outside of the draw-able area from top/bottom, we are done
    sub 159
    sub c  ; if we are drawing starting outside the buffer area, and the sprite is not tall enough 
           ; to actually overlap with the viewable area, we are done.
    ret p
    neg
    ld c, a  ; update the height of the sprite to draw
Lcf6b_skip_line_outer_loop:
    ; skip all the lines that would be drawn outside of the viewable area:
    push bc
Lcf6c_skip_line_inner_loop:
        inc de
        inc de
        djnz Lcf6c_skip_line_inner_loop
    pop bc
    dec h
    ld a, h
    cp 159
    jr nz, Lcf6b_skip_line_outer_loop
Lcf77_clip_sprite_left:
    ld a, l  ; start x coordinate
    or a
    jp p, Lcf85_clip_sprite_right
    neg  ; if sprite overflows from the left, clip sprite from the left:
    ld (Lcfaf_selfmodifying_left_pixel_skip), a
    ld l, 0  ; set drawing coordinate to 0
    cp b  ; if we are skipping the whole sprite, we are done
    ret nc
Lcf85_clip_sprite_right:
    ; See if the sprite would overflow the buffer from the right, and clip sprite from the right if 
    ; necessary:
    ld a, l  ; start x coordinate
    add a, b  ; sprite width
    cp 21
    jr c, Lcf95_calculate_buffer_pointer_to_draw_to
    sub 20  ; a now has the number of bytes we want to skip from the left of the sprite
    ld (Lcfaf_selfmodifying_left_pixel_skip), a
    ; What this loop does is to move the pointer to draw to the left, and set the number of pixels 
    ; to skip from the left, so that, effectively, we are skipping pixels from the right:
Lcf90_skip_right_pixels_initially_loop:
    dec de
    dec de
    dec a
    jr nz, Lcf90_skip_right_pixels_initially_loop
Lcf95_calculate_buffer_pointer_to_draw_to:
    push de
        ; Calculate the pointer to where we want to draw the sprite in the buffer:
        ; - l: x coordinate in bytes
        ; - h: y coordinate in pixels
        ld a, l
        push af
            ld l, h
            ld h, 0
            add hl, hl
            add hl, hl  ; hl = h*4
            ld d, h
            ld e, l
            add hl, hl
            add hl, hl
            add hl, de
        pop af
        call Ld351_add_hl_a    ; hl = h*20 + l
        ld de, L5b00_double_buffer
        add hl, de  ; hl = buffer pointer where to start drawing
    pop de
    ex de, hl
    ; Draws a sprite from "hl" to "de" ("de" points to a memory buffer with 20 bytes per row of 
    ; pixels):
    ; - b: sprite width in bytes (b*8 pixels)
    ; - c: sprite height in pixels
Lcfac_draw_loop_y:
    push bc
    push de
Lcfaf_selfmodifying_left_pixel_skip: equ $ + 1
        ld a, 0  ; mdl:self-modifying
        or a  ; if we are no skipping pixels from the left, skip the loop
        jp z, Lcfbb_draw_loop_x
        ; Skips "a*8" from the left of the sprite to draw:
Lcfb4_skip_left_pixels_loop:
        inc hl
        inc hl
        dec b
        dec a
        jp nz, Lcfb4_skip_left_pixels_loop
        ; Writes a row of "b*8" pixels from hl to de:
Lcfbb_draw_loop_x:
        ld a, (de)  ; read pixel from currently in the memory buffer
        and (hl)  ; applies and mask
        inc hl
        or (hl)  ; applies or mask
        ld (de), a  ; write pixel to the screen again
        inc hl
        inc de
        djnz Lcfbb_draw_loop_x
    pop de
    pop bc
    ; move to the previous row in the buffer (20 bytes per row, as that's the width of the in-game 
    ; area)
    ld a, -20
    add a, e
    ld e, a  ; e -= 20
    jp c, Lcfd2_no_msb_update  ; if we don't need to update the most significant byte of the buffer 
                               ; address, just skip
    dec d
    ld a, d
    cp #5a  ; we are drawing in a buffer that starts in #5b00, so, if the most-significant byte is 
            ; #5a, it means we are out of the buffer area, and we should stop drawing.
    ret z
Lcfd2_no_msb_update:
    dec c
    jp nz, Lcfac_draw_loop_y
    ret


; --------------------------------
; Clears the screen buffer in #5b00, and draws the basic map frame (thw two diagonal cut-out 
; patterns that can be seen in the game, to give the appearance of 3d).
Lcfd7_draw_blank_map_in_buffer:
    call Lcffe_clear_5b00_buffer
    call Ld026_draw_top_left_diagonal_map_edge
    ld hl, Ld6a8_diagonal_pattern1
    ld b, 6
    ld de, L5b00_double_buffer + 10
    call Ld057_draw_diagonal_line  ; draws the top-left edge of the map in screen
    ld hl, Ld6a8_diagonal_pattern1
    ld b, 3
    ld de, L5b00_double_buffer + 136*20 + 18
    call Ld057_draw_diagonal_line  ; draws the first part of the bottom-right edge of the map in 
                                   ; the screen.
    ld hl, Ld6b8_diagonal_pattern2
    ld b, 4
    ld de, L5b00_double_buffer + 128*20 + 18
    jp Ld057_draw_diagonal_line  ; draws the second part of the bottom-right edge of the map in the 
                                 ; screen.


; --------------------------------
Lcffe_clear_5b00_buffer:
    ; clears memory to 0 in the following ranges:
    ;   #5b00 - #6780 (6400 bytes)
    ld (Lfd08_stack_ptr_buffer), sp
    ld sp, L6780_graphic_patterns  ; pointer to the definition of the " " character
    ld b, 198
    ld hl, 0
    ; This loop clears from #5b20 - #6780
Ld00a:
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    push hl
    djnz Ld00a
    ld sp, (Lfd08_stack_ptr_buffer)
    ; This clears from #5b00 - #5b20. Potential optimization: just set b above to 200, and remove 
    ; the rest of this function.
    ld hl, L5b00_double_buffer
    ld de, L5b00_double_buffer+1
    ld bc, 31
    ld (hl), 0
    ldir
    ret


; --------------------------------
; Draws the top-left diagonal black part of the screen (at an 8x8 pixel resolution, the pixel-level 
; edges are drawn later in the Ld057_draw_diagonal_line function).
Ld026_draw_top_left_diagonal_map_edge:
    ld a, 10
    ld (Ld038_selfmodifying), a
    ld (Ld041_selfmodifying), a
    ld hl, L5b00_double_buffer
    ld b, 5
Ld033:
    push bc
        ld b, 8
Ld036:
        push bc
Ld038_selfmodifying: equ $ + 1
            ld b, 10  ; mdl:self-modifying
            ld a, 255
Ld03b:
            ld (hl), a
            inc hl
            djnz Ld03b
        pop bc
Ld041_selfmodifying: equ $ + 1
        ld a, 10  ; mdl:self-modifying
        call Ld351_add_hl_a
        djnz Ld036
    pop bc
    push hl
        ld hl, Ld038_selfmodifying
        dec (hl)
        dec (hl)
        ld hl, Ld041_selfmodifying
        inc (hl)
        inc (hl)
    pop hl
    djnz Ld033
    ret


; --------------------------------
; Draws one of the diagonal line patterns in either Ld6a8 or Ld6b8 to the rendering buffer
; Input:
; - hl: pointer to the source data (16 bytes)
; - de: pointer to the destination buffer to start drawing. At each repetition, we go down 8 
;       pixels, and left 16 pixels (to draw a continuous diagonal line)
; - b: number of times to copy the patterh (each time is a 16*8 pixel block). 
Ld057_draw_diagonal_line:
Ld057_draw_diagonal_line_loop:
    push bc
    push hl
        ld bc, #08ff  ; c to 255 (just a large enough value so that the auto decrement of ldi does 
                      ; not get in the way of the djnz).
        ; Draw the diagonal pattern once (16x8 pixels).
Ld05c_draw_diagonal_line_inner_loop:
        ldi
        ldi
        ld a, 18
        add a, e
        ld e, a
        ld a, d
        adc a, 0
        ld d, a  ; de += 18 (i.e., 1 line down, since each line of the buffer is 20 bytes wide, and 
                 ; each ldi already increments in one).
        djnz Ld05c_draw_diagonal_line_inner_loop
    pop hl
    pop bc
    dec de
    dec de
    djnz Ld057_draw_diagonal_line_loop
    ret


; --------------------------------
; Copies the 160x160 pixels buffer from #5b00 to video memory
Ld071_copy_game_area_buffer_to_screen:
    ld hl, L5b00_double_buffer
    ld de, L4000_VIDEOMEM_PATTERNS + 33
    ld c, 20
Ld079_row_outer_loop:
    ld b, 8
Ld07b_row_inner_loop:
    push bc
    push de
        ; copy one whole buffer row (20 bytes)
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
        ldi
    pop de
    pop bc
    inc d  ; next pixel row
    djnz Ld07b_row_inner_loop
    ; update the video pointer to the next block of 8 rows:
    ld a, e
    add a, 32
    ld e, a
    jr c, Ld0b4
    ld a, d
    sub 8
    ld d, a
Ld0b4:
    dec c
    jp nz, Ld079_row_outer_loop
    ret


; --------------------------------
; Clear the screen
Ld0b9_clear_screen:
    xor a
    out (ULA_PORT), a  ; set border to black, speaker off
    ld hl, #4000
    ld de, #4001
    ld bc, 6911
    ld (hl), 0
    ldir
    ret


; --------------------------------
Ld0ca_draw_in_game_screen_and_hud:
    call Ld0b9_clear_screen
    call Lccbd_redraw_game_area
    ; Draw white frame around the game area:
    ; Top horizontal black line 1:
    ld hl, L4000_VIDEOMEM_PATTERNS  ; (x, y) = (0, 0)
    ld de, L4000_VIDEOMEM_PATTERNS+1
    ld bc, 21
    ld (hl), 255
    ldir
    ; Top horizontal black line 2:
    ld hl, L4000_VIDEOMEM_PATTERNS + #0701  ; (x, y) = (8, 7)
    ld de, L4000_VIDEOMEM_PATTERNS + #0702
    ld bc, 19
    ld (hl), 255
    ldir
    ; Bottom horizontal black line 1:
    ld hl, L4000_VIDEOMEM_PATTERNS + #10a1  ; (x, y) = (8, 168)
    ld de, L4000_VIDEOMEM_PATTERNS + #10a2
    ld bc, 19
    ld (hl), 255
    ldir
    ; Bottom horizontal black line 2:
    ld hl, L4000_VIDEOMEM_PATTERNS + #17a0  ; (x, y) = (0, 175)
    ld de, L4000_VIDEOMEM_PATTERNS + #17a1
    ld bc, 21
    ld (hl), 255
    ldir
    ; top-left corner:
    ld hl, L4000_VIDEOMEM_PATTERNS + #0100  ; (x, y) = (0, 1)
    ld b, 6
Ld109_loop:
    ld (hl), 128
    inc h
    djnz Ld109_loop
    ; top-right corner:
    ld hl, L4000_VIDEOMEM_PATTERNS + #0115  ; (x, y) = (168, 1)
    ld b, 6
Ld113_loop:
    ld (hl), 1
    inc h
    djnz Ld113_loop
    ; bottom-left corner:
    ld hl, L4000_VIDEOMEM_PATTERNS + #10a0  ; (x, y) = (0, 168)
    ld b, 7
Ld11d_loop:
    ld (hl), 128
    inc h
    djnz Ld11d_loop
    ; bottom-right corner:
    ld hl, L4000_VIDEOMEM_PATTERNS + #10b5  ; (x, y) = (168, 168)
    ld b, 7
Ld127_loop:
    ld (hl), 1
    inc h
    djnz Ld127_loop
    ; left bar:
    ld hl, L4000_VIDEOMEM_PATTERNS + #0700  ; (x, y) = (0, 7)
    ld b, 162
Ld131_loop:
    ld (hl), 129
    call Ld32a_inc_video_ptr_y_hl
    djnz Ld131_loop
    ; right bar:
    ld hl, L4000_VIDEOMEM_PATTERNS + #0715  ; (x, y) = (128, 7)
    ld b, 162
Ld13d_loop:
    ld (hl), 129
    call Ld32a_inc_video_ptr_y_hl
    djnz Ld13d_loop

    ; Set the screen attributes:
    ; Whole thing to WHITE over BLACK to start:
    ld hl, L5800_VIDEOMEM_ATTRIBUTES
    ld de, L5800_VIDEOMEM_ATTRIBUTES + 1
    ld bc, 767
    ld (hl), COLOR_WHITE
    ldir
    ; Black over white for the frame around the game (top)""
    ; Potential optimization: If we change the pixels in the border drawing code above, we can 
    ; remove all of the lines below for the frame attributes
    ; Top line:
    ld hl, L5800_VIDEOMEM_ATTRIBUTES
    ld de, L5800_VIDEOMEM_ATTRIBUTES + 1
    ld bc, 21
    ld (hl), COLOR_BRIGHT + COLOR_WHITE * PAPER_COLOR_MULTIPLIER
    ldir
    ; Bottom line:
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #02a0
    ld de, L5800_VIDEOMEM_ATTRIBUTES + #02a0 + 1
    ld bc, 21
    ld (hl), COLOR_BRIGHT + COLOR_WHITE * PAPER_COLOR_MULTIPLIER
    ldir
    ; Side bars:
    ld hl, 22560
    ld b, 20
Ld170_loop:
    ld (hl), COLOR_BRIGHT + COLOR_WHITE * PAPER_COLOR_MULTIPLIER
    ld a, 21
    call Ld351_add_hl_a
    ld (hl), COLOR_BRIGHT + COLOR_WHITE * PAPER_COLOR_MULTIPLIER
    ld a, 11
    call Ld351_add_hl_a
    djnz Ld170_loop

    ; In-game screen yellow color:
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #0021
    ld bc, #1414  ; 20, 20
Ld186_outer_loop:
    push bc
Ld187_inner_loop:
        ld (hl), COLOR_BRIGHT + COLOR_YELLOW * PAPER_COLOR_MULTIPLIER
        inc hl
        djnz Ld187_inner_loop
    pop bc
    ld a, 12
    call Ld351_add_hl_a
    dec c
    jr nz, Ld186_outer_loop

    ; blue 3-d effect in the bottom-right of the map:
    ; Yellow -> blue border:
    ld b, 4
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #0233
Ld19a_loop:
    ld (hl), COLOR_BRIGHT + COLOR_YELLOW * PAPER_COLOR_MULTIPLIER + COLOR_BLUE
    inc hl
    ld (hl), COLOR_BRIGHT + COLOR_YELLOW * PAPER_COLOR_MULTIPLIER + COLOR_BLUE
    ld a, 29
    call Ld351_add_hl_a
    djnz Ld19a_loop
    ; Blue -> black border:
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #0253
    ld (hl), COLOR_BRIGHT + COLOR_BLUE
    inc hl
    ld (hl), COLOR_BRIGHT + COLOR_BLUE
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #0271
    ld b, 4
Ld1b3_loop:
    ld (hl), COLOR_BRIGHT + COLOR_BLUE
    inc hl
    djnz Ld1b3_loop
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #028f
    ld b, 6
Ld1bd_loop:
    ld (hl), COLOR_BRIGHT + COLOR_BLUE
    inc hl
    djnz Ld1bd_loop

    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_ATTRIBUTE, #57
        db CMD_SET_POSITION, #00, #16
        db CMD_SET_SCALE, #00
        db " DAY:"
        db CMD_NEXT_LINE
        db "TIME:"
        db CMD_SET_POSITION, #16, #00
        db CMD_SET_SCALE, #21
        db CMD_SET_ATTRIBUTE, #45
        db "RADAR:"
        db CMD_END
    ; Script end:
Ld1e5_draw_in_game_right_hud:
    call Ld2f6_clear_in_game_right_hud
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #03, #16
        db CMD_SET_ATTRIBUTE, #46
        db "  STATUS"
        db CMD_NEXT_LINE
        db "INSG  HUMN"
        db CMD_SET_POSITION, #06, #17
        db CMD_SET_ATTRIBUTE, #45
        db "WARBASES"
        db CMD_NEXT_LINE
        db "ELECTR'S"
        db CMD_NEXT_LINE
        db "NUCLEAR"
        db CMD_NEXT_LINE
        db "PHASERS"
        db CMD_NEXT_LINE
        db "MISSILES"
        db CMD_NEXT_LINE
        db " CANNON"
        db CMD_NEXT_LINE
        db "CHASSIS"
        db CMD_NEXT_LINE
        db " ROBOTS"
        db CMD_SET_POSITION, #0f, #17
        db CMD_SET_ATTRIBUTE, #46
        db "RESOURCES"
        db CMD_NEXT_LINE
        db CMD_NEXT_LINE
        db CMD_SET_ATTRIBUTE, #44
        db "GENERAL"
        db CMD_NEXT_LINE
        db "ELECTR'"
        db CMD_NEXT_LINE
        db "NUCLEAR"
        db CMD_NEXT_LINE
        db "PHASERS"
        db CMD_NEXT_LINE
        db "MISSILE"
        db CMD_NEXT_LINE
        db "CANNON"
        db CMD_NEXT_LINE
        db "CHASSIS"
        db CMD_END
    ; Script end:
Ld293_update_stats_in_right_hud:
    ld a, (Lfd39_current_in_game_right_hud)
    or a
    ret nz  ; If the stats are not to be displayed now, just return
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #10, #1e
        db CMD_SET_ATTRIBUTE, #4e
        db CMD_SET_SCALE, #00
        db CMD_END
    ; Script end:
    ; Print player resources:
    ld hl, Lfd22_player1_resource_counts
    ld b, 7
Ld2a8_player_resources_loop:
    push bc
        push hl
            call Ld470_execute_command_3_next_line
        pop hl
        ld a, (hl)
        inc hl
        push hl
            call Ld3e5_render_8bit_number
        pop hl
    pop bc
    djnz Ld2a8_player_resources_loop

    ; Print AI stats:
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #06, #16
        db CMD_SET_ATTRIBUTE, #47
        db CMD_END
    ; Script end:
    ld hl, Lfd42_player2_base_factory_counts
    call Ld2e3_draw_warbase_factory_counts
    ld a, (hl)
    call Ld3ec_render_8bit_number_with_leading_zeroes

    ; Print Player stats:
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #06, #1f
        db CMD_END
    ; Script end
    ld hl, Lfd3a_player1_base_factory_counts
    call Ld2e3_draw_warbase_factory_counts
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #0d, #1e
        db CMD_END
    ; Script end
    ld a, (hl)
    jp Ld3ec_render_8bit_number_with_leading_zeroes


; --------------------------------
; Draws the number of warbases and factories of each type a given player owns.
; Inputs:
; - hl: counts pointer
Ld2e3_draw_warbase_factory_counts:
    ld b, 7
Ld2e5_draw_warbase_factory_counts_loop:
    push bc
        ld a, (hl)
        inc hl
        add a, 48
        call Ld427_draw_character_saving_registers
        push hl
            call Ld470_execute_command_3_next_line
        pop hl
    pop bc
    djnz Ld2e5_draw_warbase_factory_counts_loop
    ret


; --------------------------------
; Clears the right-hand-size hud in-game, except for the day and time.
Ld2f6_clear_in_game_right_hud:
    call Ld42d_execute_ui_script
    ; Script start:
        db CMD_SET_POSITION, #02, #16
        db CMD_SET_SCALE, #00
        db CMD_SET_ATTRIBUTE, #00
        db CMD_END
    ; Script end:
    ld b, 22  ; Clears 22 lines (everything but the top two, which is the day and time):
Ld303_loop:
    call Ld42d_execute_ui_script
    ; Script start:
        db "          "
        db CMD_NEXT_LINE
        db CMD_END
    ; Script end:
    djnz Ld303_loop
    ret


; --------------------------------
; Input:
; - de: video pointer to draw
; - hl: sprite ptr in RAM
; - b: prite width in bytes
; - c: sprite height in pixels
Ld315_draw_masked_sprite_bottom_up:
Ld315_draw_masked_sprite_x_loop:
    push bc
    push de
Ld317_draw_masked_sprite_y_loop:
        ld a, (de)  ; get a pixel from the screen
        and (hl)    ; and mask (clear some pixels)
        inc hl     
        or (hl)     ; or mask (draw pixels)
        ld (de), a  ; write back to the screen
        inc hl      ; next pixel
        inc de
        djnz Ld317_draw_masked_sprite_y_loop
    pop de
    pop bc
    call Ld339_dec_video_ptr_y_de
    dec c
    jp nz, Ld315_draw_masked_sprite_x_loop
    ret


; --------------------------------
; Move a pointer 1 pixel down in the screen
; hl: video memory pointer as: 010ccaaa bbbxxxxx
;     The y coordinate is ccbbbaaa
Ld32a_inc_video_ptr_y_hl:
    inc h
    ld a, #07
    and h
    ret nz
    ld a, l
    add a, 32
    ld l, a
    ret c
    ld a, h
    sub 8
    ld h, a
    ret


; --------------------------------
; Move a pointer 1 pixel up in the screen
; hl: video memory pointer as: 010ccaaa bbbxxxxx
;     The y coordinate is ccbbbaaa
Ld339_dec_video_ptr_y_de:
    ld a, d
    dec d
    and #07
    ret nz
    ld a, e
    sub 32
    ld e, a
    ret c
    ld a, d
    add a, 8
    ld d, a
    ret


; --------------------------------
; input:
; - a, hl
; output:
; - hl = (hl + a*2)
Ld348_get_ptr_from_table:
    add a, a
    call Ld351_add_hl_a
    ld a, (hl)
    inc hl
    ld h, (hl)
    ld l, a
    ret


; --------------------------------
; hl = hl + a
Ld351_add_hl_a:
    add a, l
    ld l, a
    ld a, h
    adc a, 0
    ld h, a
    ret


; --------------------------------
; Random number generation: uses a 4 byte seed buffer in #fd00
; output:
; - a: next random number
; preserves: hl
Ld358_random:
    push hl
        ld hl, Lfd00_random_seed
        ld a, (hl)
        and 72
        add a, 56
        rlca
        rlca
        ld l, 3
        rl (hl)
        dec l
        rl (hl)
        dec l
        rl (hl)
        dec l
        rl (hl)
Ld370_selfmodifying: equ $ + 1
        ld l, 0  ; mdl:self-modifying
        ld a, (hl)
        and 3
        ld l, a
        ld (Ld370_selfmodifying), a  ; self-modifying: overwrites the argument of the instruction 
                                       ; marked above.
        ld a, (hl)
    pop hl
    ret


; --------------------------------
; Reads the keyboard and joystick input, and stores the state in (Lfd0c_keyboard_state).
; - If the user presses the pause key, this function is blocked until the user presses it again.
; Output:
; - a: keyboard state (also stored in "Lfd0c_keyboard_state")
Ld37c_read_keyboard_joystick_input:
    call Ld38a_read_keyboard_joystick_input_internal
    or a
    ret p  ; if pause key was not pressed, return
Ld381_pause:
    call Ld38a_read_keyboard_joystick_input_internal
    or a
    jr z, Ld381_pause
    jp m, Ld381_pause

Ld38a_read_keyboard_joystick_input_internal:
    ld hl, Ld3cc_key_pause
    ld c, 1  ; set a 1 in the least significant bit, so that when we rotate this 8 times,
             ; the carry flag is set to indicate end of iteration
Ld38f_key_loop:
    ld a, (hl)  ; keyboard matrix row to read
    inc hl
    in a, (ULA_PORT)  ; a = high byte, ULA_PORT = low byte
    and (hl)  ; mask to isolate the desired key
    inc hl
    inc hl
    ; at this point carry flag is always reset ("inc" does not touch it, and "and" resets it)
    jr nz, Ld399_key_not_pressed
    ccf  ; set carry flag
Ld399_key_not_pressed:
    rl c  ; add the bit corresponding to one key to "c" (which was in the carry flag)
    jr nc, Ld38f_key_loop  ; carry flag will be set after 8 loops (checked al 8 keys)
    ld a, (Ld3e4_input_type)
    cp INPUT_KEMPSTON
    jr z, Ld3ab_read_kempston
    cp INPUT_INTERFACE2
    jr z, Ld3b2_read_interface2
    xor a
    jr Ld3c7_all_inputs_read
Ld3ab_read_kempston:
    xor a
    in a, (KEMPSTON_JOYSTICK_PORT)  ; read the kempston joystick state
    and #1f
    jr Ld3c7_all_inputs_read
Ld3b2_read_interface2:
    ld a, INTERFACE2_JOYSTICK_PORT_MSB  ; read the interface2 joystick state.
    in a, (ULA_PORT)  ; a = high byte, ULA_PORT = low byte
    cpl
    and #1f
    ; reorder the interface2 bits so they are in the same order as they keyboard ones:
    ld b, a
    xor a
    srl b
    rla
    srl b
    rla
    srl b
    rla
    rla
    rla
    or b
Ld3c7_all_inputs_read:
    or c  ; potentially add joystick inputs over to the keyboard ones
    ld (Lfd0c_keyboard_state), a
    ret


; --------------------------------
; Array storing the redefined keys:
; - first byte is the high byte of the address to read from to get the correct keyboard matrix row.
; - the second is the mask we need to apply to the value read from the keyboard matrix to isolate 
;   the key.
; - third value is the ascii representation of the key.
Ld3cc_key_pause:
    db #f7, #01, #31  ; 247,  1, "1"
Ld3cf_key_abort:
    db #df, #04, #49  ; 223,  4, "I"
Ld3d2_key_save:
    db #f7, #10, #35  ; 247, 16, "5"
Ld3d5_key_fire:
    db #7f, #02, #82  ; 127,  2, 130
Ld3d8_key_up:
    db #fb, #01, #51  ; 251,  1, "Q"
Ld3db_key_down:
    db #fd, #01, #41  ; 253,  1, "A"
Ld3de_key_left:
    db #df, #02, #4f  ; 223,  2, "O"
Ld3e1_key_right:
    db #df, #01, #50  ; 223,  1, "P"
Ld3e4_input_type:
    db #01


; --------------------------------
Ld3e5_render_8bit_number:
    ld l, a
    ld h, 0
    ld e, ' '
    jr Ld407_render_16bit_number_2digits


; --------------------------------
Ld3ec_render_8bit_number_with_leading_zeroes:
    ld l, a
    ld h, 0
    ld e, 0
    jr Ld407_render_16bit_number_2digits


; --------------------------------
; Draws a 16bit number to screen.
; input:
; - hl: the number to draw
Ld3f3_render_16bit_number:
    ld bc, -10000
    ld e, ' '
    call Ld413_render_16bit_number_one_digit
    ld bc, -1000
    call Ld413_render_16bit_number_one_digit
Ld401_render_16bit_number_3digits:    
    ld bc, -100
    call Ld413_render_16bit_number_one_digit
Ld407_render_16bit_number_2digits:
    ld bc, -10
Ld40a:
    call Ld413_render_16bit_number_one_digit
    ld a, l
    add a, 48
    jp Ld427_draw_character_saving_registers


; --------------------------------
; - hl: number to draw.
; - bc: unit to draw (-10 for tenths, -100 for hundreds, -1000 for thousands, etc.).
; - e: filler character to use in the left for the leading zeros.
Ld413_render_16bit_number_one_digit:
    xor a
Ld414_remainder_loop:
    add hl, bc
    inc a
    jr c, Ld414_remainder_loop
    sbc hl, bc
    dec a  ; Here, a = hl / (-bc), and hl = hl % (-bc)
    jr nz, Ld424
    ld a, e
    cp 32
    jp z, Ld427_draw_character_saving_registers
    xor a
Ld424:
    inc e  ; if the filler character was a space, change it so that the rest of 
           ; empty digits are rendered as zeros.
    add a, 48  ; '0'
Ld427_draw_character_saving_registers:
    exx
        call Ld4b1_draw_character
    exx
    ret


; --------------------------------
; Executes some data-defined scripts (pointer of the script is in the stack):
; Script definition:
; - 0: end of script
; - 1: set screen coordinates
; - 2: set attribute
; - 3: next line
; - 4: set scale
; - default: render a character
; input:
; - address of data to use is in the stack
Ld42d_execute_ui_script:
    exx
Ld42e_loop:
        pop hl
        ld a, (hl)
        inc hl
        push hl
        or a
        jr z, Ld43a_done
        call Ld43c_execute_one_command
        jr Ld42e_loop
Ld43a_done:
    exx
    ret


; --------------------------------
Ld43c_execute_one_command:
    cp 1
    jr z, Ld461_execute_command_1_screen_coordinates
    cp 2
    jr z, Ld457_execute_command_2_set_attribute
    cp 3
    jr z, Ld470_execute_command_3_next_line
    cp 4
    jr z, Ld47c_execute_command_4_set_scale
    ld c, a
    ld a, (Lfd17_script_scale_x)
    or a
    ld a, c
    jr z, Ld4b1_draw_character
    jp Ld4b1_draw_character_scaled


; --------------------------------
Ld457_execute_command_2_set_attribute:
    pop de
    pop hl
        ld a, (hl)
        inc hl
    push hl
    push de
    ld (Lfd13_script_attribute), a
    ret


; --------------------------------
Ld461_execute_command_1_screen_coordinates:
    pop de
    pop hl
        ld b, (hl)
        inc hl
        ld c, (hl)
        ld (Lfd31_script_coordinate), bc
        inc hl
    push hl
    push de
    jp Ld493_compute_videomem_ptrs


; --------------------------------
Ld470_execute_command_3_next_line:
    ld bc, (Lfd31_script_coordinate)
    inc b
    ld (Lfd31_script_coordinate), bc
    jp Ld493_compute_videomem_ptrs


; --------------------------------
; Reads one byte: yyyyxxxx, and sets the scale to draw characters from
; each of the two nibbles of that byte:
; - (Lfd16_script_scale_y) = xxxx
; - (Lfd16_script_scale_y) = yyyy
; Input:
; - in the stack: ptr to read a byte from (will be incremented)
Ld47c_execute_command_4_set_scale:
    pop de
    pop hl
        ld a, (hl)
        inc hl
    push hl
    push de
    ld c, a
    rrca
    rrca
    rrca
    rrca
    and 15
    ld (Lfd16_script_scale_y), a
    ld a, c
    and 15
    ld (Lfd17_script_scale_x), a
    ret


; --------------------------------
; Recalculate pattern table and attribute table pointers
; input:
; - bc: value of Lfd31_script_coordinate
; output:
; - Lfd04_script_video_pattern_ptr
; - Lfd14_script_video_attribute_ptr
Ld493_compute_videomem_ptrs:
    ld a, b
    and 248  ; #f8
    add a, 64
    ld h, a  ; h = (b & #f8) + 64
    ld a, b
    and 7
    rrca
    rrca
    rrca
    add a, c
    ld l, a  ; l = "high 3 bits of b" + c
    ld (Lfd04_script_video_pattern_ptr), hl
    ld a, h
    rrca
    rrca
    rrca
    and 3
    or 88
    ld h, a
    ld (Lfd14_script_video_attribute_ptr), hl
    ret


; --------------------------------
; input:
; - a: character to draw
; - (Lfd04_script_video_pattern_ptr) pointer to draw it to in video memory (will be incremented)
; - (Lfd14_script_video_attribute_ptr) pointer to set the attributes in video memory (will be 
;   incremented).
Ld4b1_draw_character:
    ld h, 0
    ld l, a
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, L6780_graphic_patterns - 32*8  ; there is only data for characters starting at ' ' (32)
    add hl, de  ; hl = a * 8 + #6680 : get ptr to character to draw
    ld de, (Lfd04_script_video_pattern_ptr)
    push de
        ld b, 8
Ld4c2_loop:
        ld a, (hl)
        ld (de), a
        inc hl
        inc d
        djnz Ld4c2_loop
    pop de
    inc de
    ld (Lfd04_script_video_pattern_ptr), de
    ld hl, (Lfd14_script_video_attribute_ptr)
    ld a, (Lfd13_script_attribute)
    ld (hl), a
    inc hl
    ld (Lfd14_script_video_attribute_ptr), hl
    ret


; --------------------------------
; input:
; - a: character to draw
Ld4b1_draw_character_scaled:
    ld h, 0
    ld l, a
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, L6780_graphic_patterns - 32*8  ; there is only data for characters starting at ' ' (32)
    add hl, de  ; hl = a * 8 + #6680 : get ptr to character to draw
    ld a, (Lfd17_script_scale_x)
    cp 2
    jr nc, Ld502
    ex de, hl
    ld hl, (Lfd04_script_video_pattern_ptr)
    ld c, 8
Ld4f1:
    ld a, (Lfd16_script_scale_y)
    ld b, a
Ld4f5:
    ld a, (de)
    ld (hl), a
    call Ld32a_inc_video_ptr_y_hl
    djnz Ld4f5
    inc de
    dec c
    jr nz, Ld4f1
    jr Ld532
Ld502:
    push ix
        push hl
        pop ix
        ld hl, (Lfd04_script_video_pattern_ptr)
        ld c, 8
Ld50c:
        ld a, (ix)
        ld b, 8
Ld511:
        rlca
        push af
            rl e
            rl d
        pop af
        rl e
        rl d
        djnz Ld511
        ld a, (Lfd16_script_scale_y)
        ld b, a
Ld522:
        ld (hl), d
        inc l
        ld (hl), e
        dec l
        call Ld32a_inc_video_ptr_y_hl
        djnz Ld522
        inc ix
        dec c
        jr nz, Ld50c
    pop ix
Ld532:
    ld hl, (Lfd04_script_video_pattern_ptr)
    ld a, (Lfd17_script_scale_x)
    call Ld351_add_hl_a
    ld (Lfd04_script_video_pattern_ptr), hl
    ld hl, (Lfd14_script_video_attribute_ptr)
    push hl
        ld bc, (Lfd16_script_scale_y)
        ld a, (Lfd13_script_attribute)
        ld e, a
Ld54a:
        push hl
        push bc
Ld54c:
            ld (hl), e
            inc hl
            djnz Ld54c
        pop bc
        pop hl
        ld a, l
        add a, 32
        ld l, a
        ld a, h
        adc a, 0
        ld h, a
        dec c
        jr nz, Ld54a
    pop hl
    ld a, b
    call Ld351_add_hl_a
    ld (Lfd14_script_video_attribute_ptr), hl
    ret


; --------------------------------
; Interrupt handler routine
Ld566_interrupt:
    push af
    push bc
    push de
    push hl
        ; Increments the # of interrupts counter (for game timing purposes):
        ld hl, Lfd34_n_interrupts_this_came_cycle
        inc (hl)
        ; Draw the radar (flickering):
        ; Player and enemy robots are drawn to view1 and view2 respectively, and in this way, when 
        ; showing them, they show in different colors.
        ld hl, Ld800_radar_view1
        ld c, COLOR_BRIGHT + COLOR_CYAN + PAPER_COLOR_MULTIPLIER * COLOR_BLUE
        ld a, (Lfd1a_interrupt_parity)
        xor 1
        ld (Lfd1a_interrupt_parity), a
        jr z, Ld582_radar_flicker
        ld hl, Ld900_radar_view2
        ld c, COLOR_BRIGHT + COLOR_YELLOW + PAPER_COLOR_MULTIPLIER * COLOR_BLUE
Ld582_radar_flicker:
        call Ld59e_draw_radar
        ld a, (Lfd53_produce_in_game_sound)
        or a
        jr z, Ld598_no_sound
        inc a
        cp 128
        jr nz, Ld591_keep_sound
        xor a
Ld591_keep_sound:
        ld (Lfd53_produce_in_game_sound), a
        or a
        call nz, Ld5c4_produce_in_game_sound
Ld598_no_sound:
    pop hl
    pop de
    pop bc
    pop af
Ld59c_empty_interrupt:
    ei
    ret


; --------------------------------
; Draws the radar view to video memory
Ld59e_draw_radar:
    ; Draw the radar to video memory:
    push bc
        ld b, 16
        ld de, L4000_VIDEOMEM_PATTERNS + #10c6  ; pointer to the "radar" view in video memory
Ld5a4_draw_radar_loop_y:
        push bc
            push de
                ; Copy a radar row (16 bytes wide)
                ld bc, 16
                ldir
            pop de
            ex de, hl
                call Ld32a_inc_video_ptr_y_hl
            ex de, hl
        pop bc
        djnz Ld5a4_draw_radar_loop_y
    pop bc
    ; Set the attributes:
    ld hl, L5800_VIDEOMEM_ATTRIBUTES + #02c6  ; pointer to the attributes of the radar
    call Ld5bd_set_radar_attributes_one_row
    ld l, #e6  ; second line
Ld5bd_set_radar_attributes_one_row:
    ld b, 16
Ld5bf_radar_attributes_loop_x:
    ld (hl), c
    inc hl
    djnz Ld5bf_radar_attributes_loop_x
    ret


; --------------------------------
; Produces in-game sound based on the value of "a".
; There are two types of possible sounds:
; - if a is positive, it'll produce some sound based on reading values from ROM (starting at 0 
;   address).
; - if a is negative, it produces sound based on the random number generator.
; Input:
; - a: type of sound to produce
Ld5c4_produce_in_game_sound:
    jp m, Ld5ec_random_noise
    ; if "a" is positive, produce a different type of sound: 
    ld b, a
    inc a
    inc a
    ld hl, 500
    ld e, a
    ld d, 0
    ld c, 0
    xor a
Ld5d3:
    inc c
    sbc hl, de
    jr nc, Ld5d3
    ld hl, 0  ; read values from the ROM at this address (which will be noise, but a different type 
              ; of noise).
Ld5db:
    push bc
        ld a, (hl)
        inc hl
        and 16
        out (ULA_PORT), a  ; change MIC/EAR state (to produce sound)
Ld5e2:
        djnz Ld5e2
    pop bc
    dec c
    jr nz, Ld5db
    xor a
    out (ULA_PORT), a  ; change MIC/EAR state (sound off)
    ret


; --------------------------------
; Produce random noise for a short period of time:
Ld5ec_random_noise:
    ld b, 30
Ld5ee_loop:
    call Ld358_random
    and 16
    out (ULA_PORT), a  ; change MIC/EAR state (to produce sound)
    djnz Ld5ee_loop
    ret


; --------------------------------
; Updates the two radar buffers (Ld800_radar_view1, Ld800_radar_view2) with all the 
; buildings and robots in the map.
Ld5f8_update_radar_buffers:
    ld hl, Ld800_radar_view1
    ld de, (Lfd1c_radar_scroll_x)
    ld a, d
    add a, #dd
    ld d, a  ; de now has the pointer to the map buffer (Ldd00_map) corresponding to the radar view
    ; Updates the contents of the radar:
    ld bc, #1010  ; 16, 16
Ld606_radar_update_loop_y:
    push bc
    push de
Ld608_radar_update_loop_x:
        push bc
            ld b, 8
Ld60b_radar_update_loop_byte:
            ld a, (de)
            inc de
            and #1f
            cp #0f
            ccf  ; carry = 1 if the map has an element > 15 (building)
            rl (hl)  ; this inserts a 0/1 from the left of the byte. Since we iterate this loop 8 
                     ; times, it will eventually replace the old value of this byte in the radar 
                     ; buffer.
            djnz Ld60b_radar_update_loop_byte
            inc hl
        pop bc
        djnz Ld608_radar_update_loop_x
    pop de
    pop bc
    ; increment "y":
    inc d
    inc d
    dec c
    jr nz, Ld606_radar_update_loop_y

    ; Sync both radar views:    
    ld hl, Ld800_radar_view1  ; player and player robots will be drawn to view 1
    ld de, Ld900_radar_view2  ; enemy robots are drawn to view 2
    ld bc, 256
    ldir

    ; Update robots in the radar view:
    ld iy, Lda00_player1_robots
    ld b, MAX_ROBOTS_PER_PLAYER * 2
Ld632:
    push bc
        ld a, (iy + 1)
        or a
        jr z, Ld651_next_robot  ; If there is no robot in this struct, skip
        ld l, (iy + ROBOT_STRUCT_X)
        ld h, (iy + ROBOT_STRUCT_X + 1)
        ld c, (iy + ROBOT_STRUCT_Y)
        ld a, (iy + ROBOT_STRUCT_CONTROL)
        rlca
        and 1
        ld b, a  ; b = 0 if player robot, and b = 1 if enemy robot.
        ld a, (iy + ROBOT_STRUCT_CONTROL)
        cp 2
        call nz, Ld65a_flip_2x2_radar_area
Ld651_next_robot:
        ld de, ROBOT_STRUCT_SIZE
        add iy, de
    pop bc
    djnz Ld632
    ret


; --------------------------------
; Flicker a 2x2 area in the radar view. This function will get the pointer
; in the radar view corresponding to the given coordinates, and then flip
; the bits in a 2x2 area around it.
; Input:
; - hl: x coordinate
; - b: whether to use Ld800_radar_view1 (b == 0), or Ld900_radar_view2 (b == 1)
; - c: y coordinate
Ld65a_flip_2x2_radar_area:
    call Ld67d_get_radar_view_pointer
    ld c, a
    ; Flip the first row of 2 bits:
    push hl
        ld a, (hl)
        xor c
        ld (hl), a
        rrc c
        jr nc, Ld667_not_crossing_to_the_next_byte
        inc hl
Ld667_not_crossing_to_the_next_byte:
        ld a, (hl)
        xor c
        ld (hl), a
    pop hl
    ; Flip the next row of 2 bits:
    ld a, l
    sub 16
    ld l, a
    rlc c
    ld a, (hl)
    xor c
    ld (hl), a
    rrc c
    jr nc, Ld679_not_crossing_to_the_next_byte
    inc hl
Ld679_not_crossing_to_the_next_byte:
    ld a, (hl)
    xor c
    ld (hl), a
    ret


; --------------------------------
; Get radar view pointer
; input:
; - hl: x coordinate
; - b: whether to use Ld800_radar_view1 (b == 0), or Ld900_radar_view2 (b == 1)
; - c: y coordinate
; output:
; - a: bit (one-hot representation) that corresponds to the given coordinates.
; - hl: byte in the radar view that corresponds to the given coordinates.
Ld67d_get_radar_view_pointer:
    ld de, (Lfd1c_radar_scroll_x)
    xor a
    sbc hl, de
    ld a, h
    or a
    ; return if when we subtracted "de" from the x coordinate, we don't get a number between 0 and 
    ; 127:
    jr nz, Ld6a6_exit
    ld a, l
    cp 127
    jr nc, Ld6a6_exit

    ; here we know that hl - de is on [0,127]
    ld a, Ld800_radar_view1 / 256
    add a, b
    ld h, a  ; h = b + #d8
    ld a, l
    and #07
    inc a
    ld b, a  ; b = ((hl - de)%8) + 1
    ld a, l
    rlca  ; a = (hl - de)*2  ->  xxxxxxx0
    and #f0  ; We keep only the upper 4 bits  ->  xxxx0000
    or c  ; xxxxyyyy
    rlca
    rlca
    rlca
    rlca
    ld l, a  ; a = yyyyxxxx. Where yyyy is the y coordinate (in c), and xxxx are bits 3-6 of hl-de
    xor a
    scf
Ld6a2_shift_loop:
    rra
    djnz Ld6a2_shift_loop
    ; here "a" is a one-hot representation of (hl - de)%8
    ret
Ld6a6_exit:
    pop hl  ; simulate a ret (so, we return from Ld65a_flip_2x2_radar_area, which is the only 
            ; caller of this function)
    ret


; --------------------------------
Ld6a8_diagonal_pattern1:  ; diagonal line (top-left painted, bottom-left empty)
    db #ff, #ff, #ff, #fc, #ff, #f0, #ff, #c0, #ff, #00, #fc, #00, #f0, #00, #c0, #00
Ld6b8_diagonal_pattern2:  ; diagonal line (top-left empty, bottom-left painted)
    db #00, #03, #00, #0f, #00, #3f, #00, #ff, #03, #ff, #0f, #ff, #3f, #ff, #ff, #ff


; --------------------------------
Ld6c8_piece_direction_graphic_indices:
    ; Index of the graphic to draw for each piece in each of the 4 cardinal directions.
    ; For example, notice how "nuclear" has the same graphic regardless of the direction.
    ; To find the specific graphic in the "Ld740_isometric_graphic_pointers" table below,
    ; multiply the index by 2 (as each graphic is stored twice, one with a precalculated
    ; offset of 4 pixels).
    db 2, 2, 3, 3  ; bipod
    db 0, 0, 1, 1  ; tracks
    db 4, 4, 4, 4  ; antigrav
    db 5, 6, 7, 8  ; cannon
    db 9, 9, 10, 10  ; missiles
    db 11, 12, 13, 14  ; phasers
    db 15, 15, 15, 15  ; nuclear
    db 16, 17, 18, 19  ; electronics


; --------------------------------
Ld6e8_additional_isometric_graphic_pointers:  ; 44 pointers
    dw L8e3a_iso_additional_graphic_0
    dw L8f2c_iso_additional_graphic_1
    dw L901e_iso_additional_graphic_2
    dw L90b0_iso_additional_graphic_3
    dw L9172_iso_additional_graphic_4
    dw L9172_iso_additional_graphic_4
    dw L91f2_iso_additional_graphic_5
    dw L91f2_iso_additional_graphic_5
    dw L9278_iso_additional_graphic_6
    dw L9278_iso_additional_graphic_6
    dw L92f8_iso_additional_graphic_7
    dw L92f8_iso_additional_graphic_7
    dw L9d9c_iso_additional_graphic_22
    dw L9e34_iso_additional_graphic_23
    dw L9ef6_iso_additional_graphic_24
    dw L9f8e_iso_additional_graphic_25
    dw L9372_iso_additional_graphic_8
    dw L9372_iso_additional_graphic_8
    dw L940a_iso_additional_graphic_9
    dw L940a_iso_additional_graphic_9
    dw L94a8_iso_additional_graphic_10
    dw L94a8_iso_additional_graphic_10
    dw L9534_iso_additional_graphic_11
    dw L9534_iso_additional_graphic_11
    dw L95c6_iso_additional_graphic_12
    dw L9640_iso_additional_graphic_13
    dw L96ea_iso_additional_graphic_14
    dw L9776_iso_additional_graphic_15
    dw L9820_iso_additional_graphic_16
    dw L98ac_iso_additional_graphic_17
    dw L9914_iso_additional_graphic_18
    dw L9a16_iso_additional_graphic_19
    dw L9b18_iso_additional_graphic_20
    dw L9c5a_iso_additional_graphic_21
    dw La0e2_iso_additional_graphic_27
    dw La1e4_iso_additional_graphic_28
    dw La2e6_iso_additional_graphic_29
    dw La428_iso_additional_graphic_30
    dw L8e3a_iso_additional_graphic_0
    dw L8e3a_iso_additional_graphic_0
    dw L8e3a_iso_additional_graphic_0
    dw L8e3a_iso_additional_graphic_0
    dw La050_iso_additional_graphic_26
    dw La050_iso_additional_graphic_26

Ld740_isometric_graphic_pointers:  ; 58 pointers
    dw L6980_iso_graphic_0  ; tracks
    dw L6a24_iso_graphic_1
    dw L6afe_iso_graphic_2
    dw L6ba8_iso_graphic_3
    dw L6c8a_iso_graphic_4  ; bipod
    dw L6d40_iso_graphic_5
    dw L6e32_iso_graphic_6
    dw L6ee2_iso_graphic_7
    dw L6fcc_iso_graphic_8  ; antigrav
    dw L7058_iso_graphic_9
    dw L7112_iso_graphic_10  ; cannon
    dw L71bc_iso_graphic_11
    dw L729e_iso_graphic_12
    dw L7354_iso_graphic_13
    dw L7446_iso_graphic_14
    dw L74fc_iso_graphic_15
    dw L75ee_iso_graphic_16
    dw L7686_iso_graphic_17
    dw L7750_iso_graphic_18  ; missiles
    dw L77f4_iso_graphic_19
    dw L78ce_iso_graphic_20
    dw L7978_iso_graphic_21
    dw L7a5a_iso_graphic_22  ; phaser
    dw L7b04_iso_graphic_23
    dw L7be6_iso_graphic_24
    dw L7c96_iso_graphic_25
    dw L7d80_iso_graphic_26
    dw L7e30_iso_graphic_27
    dw L7f1a_iso_graphic_28
    dw L7fb8_iso_graphic_29
    dw L808a_iso_graphic_30  ; nuclear
    dw L813a_iso_graphic_31
    dw L8224_iso_graphic_32
    dw L82b6_iso_graphic_33
    dw L8348_iso_graphic_34
    dw L83da_iso_graphic_35
    dw L846c_iso_graphic_36
    dw L84fe_iso_graphic_37
    dw L8590_iso_graphic_38
    dw L8622_iso_graphic_39
    dw L86b4_iso_graphic_40
    dw L86f8_iso_graphic_41
    dw L8752_iso_graphic_42
    dw L8796_iso_graphic_43
    dw L87f0_iso_graphic_44
    dw L8858_iso_graphic_45
    dw L88e2_iso_graphic_46
    dw L8924_iso_graphic_47
    dw L8966_iso_graphic_48
    dw L89b6_iso_graphic_49
    dw L8a06_iso_graphic_50
    dw L8a8c_iso_graphic_51
    dw L8b3e_iso_graphic_52
    dw L8bc4_iso_graphic_53
    dw L8c76_iso_graphic_54
    dw L8cde_iso_graphic_55
    dw L8d46_iso_graphic_56
    dw L8dc0_iso_graphic_57


; --------------------------------
Ld7b4_piece_heights:  
    db 11  ; bipod
    db 7  ; tracks
    db 8  ; antigrav
    db 6  ; cannon
    db 6  ; missiles
    db 7  ; phasers
    db 7  ; nuclear
    db 7  ; electronics

Ld7bc_map_piece_heights:  ; 23 elements
    db #00, #00, #02, #02, #02, #02, #03, #03, #06, #06, #06, #06, #00, #00, #00, #07
    db #0f, #07, #0f, #00, #00, #63, #00


; --------------------------------
; RAM Variables:
Ld7d3_bullets: equ #d7d3  ; 5 * 9 bytes
Ld800_radar_view1: equ #d800  ; 256 bytes. Player and player robots are drawn here
Ld900_radar_view2: equ #d900  ; 256 bytes. Enemy robots are drawn here


; When saving a game, RAM is stored starting from here:
Ld92b_save_game_start: equ #d92b  ; 213 bytes, buffer where a few things are copied before saving a 
                                  ; game: bullet state (45 bytes), and 168 bytes from 
                                  ; Lff01_building_decorations.
Lda00_player1_robots: equ #da00  ; 384 bytes  (24 robots * 16 bytes per robot)
Ldb80_player2_robots: equ #db80  ; 384 bytes  (24 robots * 16 bytes per robot)

; Each byte of the map is organized as:
; - dcbaaaaa:
;     - aaaaa: element type
;     - b: as elements use a 2x2 position, only the bottom-left corner has this as 0
;     - c: indicates a robot/factory/warbase is here
;     - d: indicates player is here
Ldd00_map: equ #dd00  ; map: 512*16 = 8192 bytes

Lfd00_random_seed: equ #fd00  ; 4 bytes
Lfd04_script_video_pattern_ptr: equ #fd04  ; 2 bytes
Lfd06_scroll_ptr: equ #fd06  ; 2 bytes
Lfd08_stack_ptr_buffer: equ #fd08  ; 2 bytes
Lfd0a_scroll_x: equ #fd0a  ; 2 bytes
Lfd0c_keyboard_state: equ #fd0c  ; 1 byte
Lfd0d_player_y: equ #fd0d  ; 1 byte. Narrow axis of the map.
Lfd0e_player_x: equ #fd0e  ; 2 bytes. Long axis of the map
Lfd10_player_altitude: equ #fd10  ; 1 byte.
Lfd11_player_iso_coordinates_if_deferred: equ #fd11  ; 2 bytes. If rendering of the player is 
                                                     ; sprite is deferred due to an overlapping 
                                                     ; sprite, this will contain the original 
                                                     ; isometric coordinates of the player sprite.
Lfd13_script_attribute: equ #fd13  ; 1 byte
Lfd14_script_video_attribute_ptr: equ #fd14  ; 2 bytes
Lfd16_script_scale_y: equ #fd16  ; 1 byte
Lfd17_script_scale_x: equ #fd17  ; 1 byte
; 2 unused bytes
Lfd1a_interrupt_parity: equ #fd1a  ; 1 byte. Used to determine if we are in an even or odd 
                                   ; interrupt call.
Lfd1b_radar_scroll_x_tile: equ #fd1b  ; 1 byte. Same as the variable below, but at tile resolution.
Lfd1c_radar_scroll_x: equ #fd1c  ; 2 bytes
Lfd1e_player_visible_in_radar: equ #fd1e  ; 1 byte. The least-significant bit of this variable 
                                          ; represents whether to draw the player in the radar or 
                                          ; not. It's used to make the player blink.
Lfd1f_cursor_position: equ #fd1f  ; 2 bytes: x, y
Lfd21_construction_selected_pieces: equ #fd21  ; 1 byte
Lfd22_player1_resource_counts: equ #fd22  ; 7 bytes
Lfd29_resource_counts_buffer: equ #fd29  ; 7 bytes. Used, for example, in the robot construction 
                                         ; screen, to keep track of resources left after the 
                                         ; selected pieces are discounted from the resources.
Lfd30_player_elevate_timer: equ #fd30  ; 1 byte. If this is > 0, player ship elevates 
                                       ; automatically, until this reaches 0 (used when exiting a 
                                       ; robot / warbase, for example).
Lfd31_script_coordinate: equ #fd31  ; 2 bytes
Lfd33_title_color: equ #fd33  ; 1 byte. Used only in the title screen to do title color rotation.
Lfd34_n_interrupts_this_came_cycle: equ #fd34  ; 1 byte
Lfd35_minutes: equ #fd35  ; 1 byte
Lfd36_hours: equ #fd36  ; 1 byte
Lfd37_days: equ #fd37  ; 2 bytes
Lfd39_current_in_game_right_hud: equ #fd39  ; 1 byte. Stores which is the info/menu to display in 
                                            ; the right hud.
Lfd3a_player1_base_factory_counts: equ #fd3a  ; 7 bytes
Lfd41_player1_robot_count: equ #fd41  ; 1 byte
Lfd42_player2_base_factory_counts: equ #fd42  ; 7 bytes
Lfd49_player2_robot_count: equ #fd49  ; 1 byte
Lfd4a_player2_resource_counts: equ #fd4a  ; 7 bytes
Lfd51_current_robot_player_or_enemy: equ #fd51  ; 1 byte. Used to indicate if the robot we are 
                                                ; working with is controlled by the player or the 
                                                ; enemy AI. (0: player, 1: enemy AI).
Lfd52_update_radar_buffer_signal: equ #fd52  ; 1 byte. If this is set to 1, the radar buffer will 
                                             ; be updated this cycle.
Lfd53_produce_in_game_sound: equ #fd53  ; 1 byte. When != 0, it will make the game interrupt 
                                        ; produce some sound, incrementing once per cycle until 
                                        ; reaching 128 or 0, at which point the sound it will stop.
Lfd54_music_channel1_ret_address: equ #fd54  ; 2 bytes
Lfd56_music_channel2_ret_address: equ #fd56  ; 2 bytes
; 24 unused bytes
Lfd70_warbases: equ #fd70
Lfd84_factories: equ Lfd70_warbases + N_WARBASES * BUILDING_STRUCT_SIZE
Lfdfc_save_game_end: equ #fdfc ; When saving a game, RAM is stored up to here.


Lfdfd_interrupt_jp: equ #fdfd  ; 1 byte
Lfdfe_interrupt_pointer: equ #fdfe  ; 2 bytes
Lfe00_interrupt_vector_table: equ #fe00  ; 257 bytes
Lff01_building_decorations: equ #ff01  ; 56 structs of 3 bytes each: map ptr (2 bytes), type (1 
                                       ; byte)

