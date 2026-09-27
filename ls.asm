bits 16
cpu 8086
org 0
%define ENTRY_SIZE 22
%define MAX_ENTRIES 512

; DOS 6.22 directory lister for 8086/8088 systems.
; The build script wraps this flat load module in a 32-byte MZ header.

start:
    push cs
    pop ds
    push ds
    pop es

    mov dx, dta
    mov ah, 1Ah
    int 21h

    call parse_command_line
    jc usage_error

    push ds
    pop es
    call resolve_color_mode
    cmp byte [help_flag], 0
    jne show_help

    mov si, path_buffer
    call prepare_search
    jc search_error

    mov dx, search_buffer
    mov cx, 0010h
    cmp byte [show_all], 0
    je .find_first
    mov cx, 0037h
.find_first:
    mov ah, 4Eh
    int 21h
    jc no_matches

.next_entry:
    call should_print_entry
    jc .advance
    call save_entry
    jc too_many_entries
.advance:
    mov ah, 4Fh
    int 21h
    jnc .next_entry

    cmp word [entry_count], 0
    je no_matches
    call sort_entries
    cmp byte [long_format], 0
    jne .display_single_column
    cmp byte [column_mode], 0
    je .display_single_column
    call display_columns
    mov ax, 4C00h
    int 21h
.display_single_column:
    mov word [display_index], 0
.display_entry:
    mov ax, [display_index]
    cmp ax, [entry_count]
    jae .listing_done
    mov si, sort_table
    mov cx, ax
.record_offset:
    jcxz .record_ready
    add si, ENTRY_SIZE
    loop .record_offset
.record_ready:
    push si
    mov di, dta+1Eh
    mov cx, 13
    rep movsb
    pop si
    mov al, [si+13]
    mov [dta+15h], al
    mov ax, [si+14]
    mov [dta+16h], ax
    mov ax, [si+16]
    mov [dta+18h], ax
    mov ax, [si+18]
    mov [dta+1Ah], ax
    mov ax, [si+20]
    mov [dta+1Ch], ax
    call print_entry
    inc word [display_index]
    jmp .display_entry
.listing_done:
    mov ax, 4C00h
    int 21h

too_many_entries:
    mov dx, too_many_message
    call print_dollar_string
    mov ax, 4C03h
    int 21h

usage_error:
    mov dx, usage_message
    call print_dollar_string
    mov ax, 4C02h
    int 21h

show_help:
    mov dx, help_message
    call print_dollar_string
    mov ax, 4C00h
    int 21h

search_error:
    mov dx, path_error_message
    call print_dollar_string
    mov ax, 4C01h
    int 21h

no_matches:
    mov dx, no_matches_message
    call print_dollar_string
    mov ax, 4C01h
    int 21h

; Copies the PSP tail, tokenizes it, handles flags, and records one operand.
; CF is set for an invalid option or multiple operands.
parse_command_line:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov ah, 62h
    int 21h
    mov es, bx
    xor cx, cx
    mov cl, [es:80h]
    mov si, 81h
    mov di, command_buffer
.copy_tail:
    jcxz .tail_done
    mov al, [es:si]
    cmp al, 0Dh
    je .tail_done
    mov [di], al
    inc si
    inc di
    loop .copy_tail
.tail_done:
    mov byte [di], 0
    push ds
    pop es

    mov si, command_buffer
.skip_space:
    cmp byte [token_ended], 0
    jne .end_tokens
    lodsb
    cmp al, ' '
    je .skip_space
    cmp al, 9
    je .skip_space
    dec si

.token:
    mov di, token_buffer
    xor cx, cx
.copy_token:
    lodsb
    cmp al, 0
    je .token_done
    cmp al, 0Dh
    je .token_done
    cmp al, ' '
    je .token_done
    cmp al, 9
    je .token_done
    stosb
    inc cx
    jmp .copy_token
.token_done:
    mov byte [di], 0
    mov byte [token_ended], 0
    or al, al
    jnz .token_delimited
    mov byte [token_ended], 1
.token_delimited:
    cmp cx, 0
    je .end_tokens

    cmp byte [token_buffer], '-'
    jne .operand
    cmp byte [token_buffer+1], '-'
    je .long_option
    cmp byte [token_buffer+1], 'h'
    jne .short_options
    cmp byte [token_buffer+2], 'e'
    jne .short_options
    cmp byte [token_buffer+3], 'l'
    jne .short_options
    cmp byte [token_buffer+4], 'p'
    jne .short_options
    cmp byte [token_buffer+5], 0
    jne .short_options
    mov byte [help_flag], 1
    jmp .skip_space
.short_options:
    mov [command_cursor], si
    mov si, token_buffer+1
.short_flags:
    lodsb
    or al, al
    jz .short_options_done
    cmp al, 'f'
    je .fast
    cmp al, 'a'
    je .all_lower
    cmp al, 'r'
    je .reverse
    cmp al, 's'
    je .invalid
    cmp al, 'u'
    je .invalid
    cmp al, 'c'
    je .invalid
    cmp al, 'H'
    je .invalid
    cmp al, 'R'
    je .invalid
    cmp al, 'L'
    je .invalid
    cmp al, 'P'
    je .invalid
    cmp al, 'T'
    je .invalid
    and al, 0DFh
    cmp al, 'A'
    je .all
    cmp al, 'L'
    je .long
    cmp al, '1'
    je .one_column
    cmp al, 'F'
    je .classify
    cmp al, 'P'
    je .slash_dirs
    cmp al, 'C'
    je .multiple_columns
    cmp al, 'H'
    je .human
    cmp al, 'R'
    je .reverse
    cmp al, 'T'
    je .sort_time
    cmp al, 'S'
    je .sort_size
    cmp al, 'U'
    je .unsorted
    jmp .invalid
.short_options_done:
    mov si, [command_cursor]
    jmp .skip_space
.all:
    mov byte [show_all], 1
    jmp .short_flags
.all_lower:
    mov byte [show_all], 1
    mov byte [show_dots], 1
    jmp .short_flags
.long:
    mov byte [long_format], 1
    mov byte [column_mode], 0
    jmp .short_flags
.one_column:
    mov byte [column_mode], 0
    jmp .short_flags
.classify:
    mov byte [classify_names], 1
    jmp .short_flags
.slash_dirs:
    mov byte [slash_directories], 1
    jmp .short_flags
.multiple_columns:
    mov byte [column_mode], 1
    jmp .short_flags
.human:
    mov byte [human_size], 1
    mov byte [long_format], 1
    mov byte [column_mode], 0
    jmp .short_flags
.reverse:
    mov byte [reverse_order], 1
    jmp .short_flags
.sort_time:
    mov byte [sort_mode], 1
    jmp .short_flags
.sort_size:
    mov byte [sort_mode], 2
    jmp .short_flags
.unsorted:
    mov byte [unsorted_order], 1
    jmp .short_flags
.fast:
    mov byte [show_all], 1
    mov byte [show_dots], 1
    mov byte [unsorted_order], 1
    mov byte [color_mode], 0
    mov byte [column_mode], 0
    jmp .short_flags

.long_option:
    cmp byte [token_buffer+2], 'h'
    jne .check_color
    cmp byte [token_buffer+3], 'e'
    jne .check_color
    cmp byte [token_buffer+4], 'l'
    jne .check_color
    cmp byte [token_buffer+5], 'p'
    jne .check_color
    cmp byte [token_buffer+6], 0
    jne .check_color
    mov byte [help_flag], 1
    jmp .skip_space
.check_color:
    cmp word [token_buffer], 2D2Dh
    jne .invalid
    cmp byte [token_buffer+2], 'c'
    jne .invalid
    cmp byte [token_buffer+3], 'o'
    jne .invalid
    cmp byte [token_buffer+4], 'l'
    jne .invalid
    cmp byte [token_buffer+5], 'o'
    jne .invalid
    cmp byte [token_buffer+6], 'r'
    jne .check_bare_color
    cmp byte [token_buffer+7], '='
    jne .check_bare_color
    cmp byte [token_buffer+8], 'a'
    jne .check_never
    cmp byte [token_buffer+9], 'l'
    jne .invalid
    cmp byte [token_buffer+10], 'w'
    jne .invalid
    cmp byte [token_buffer+11], 'a'
    jne .invalid
    cmp byte [token_buffer+12], 'y'
    jne .invalid
    cmp byte [token_buffer+13], 's'
    jne .invalid
    cmp byte [token_buffer+14], 0
    jne .invalid
    mov byte [color_mode], 1
    jmp .skip_space
.check_never:
    cmp byte [token_buffer+8], 'n'
    jne .check_auto
    cmp byte [token_buffer+9], 'e'
    jne .invalid
    cmp byte [token_buffer+10], 'v'
    jne .invalid
    cmp byte [token_buffer+11], 'e'
    jne .invalid
    cmp byte [token_buffer+12], 'r'
    jne .invalid
    cmp byte [token_buffer+13], 0
    jne .invalid
    mov byte [color_mode], 0
    jmp .skip_space
.check_auto:
    cmp byte [token_buffer+8], 'a'
    jne .invalid
    cmp byte [token_buffer+9], 'u'
    jne .invalid
    cmp byte [token_buffer+10], 't'
    jne .invalid
    cmp byte [token_buffer+11], 'o'
    jne .invalid
    cmp byte [token_buffer+12], 0
    jne .invalid
    mov byte [color_mode], 2
    jmp .skip_space
.check_bare_color:
    cmp byte [token_buffer+6], 'r'
    jne .invalid
    cmp byte [token_buffer+7], 0
    jne .invalid
    mov byte [color_mode], 1
    jmp .skip_space

.operand:
    cmp byte [have_path], 0
    jne .invalid
    mov si, token_buffer
    mov di, path_buffer
.copy_path:
    lodsb
    stosb
    or al, al
    jnz .copy_path
    mov byte [have_path], 1
    jmp .skip_space

.end_tokens:
    clc
    jmp .parse_done
.invalid:
    stc
.parse_done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; Turn a directory operand into DIR\*.*. Wildcard or file operands pass through.
prepare_search:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    mov di, si
    mov bx, si
.scan_path:
    mov al, [si]
    or al, al
    jz .path_scanned
    cmp al, '*'
    je .use_as_is
    cmp al, '?'
    je .use_as_is
    inc si
    jmp .scan_path
.path_scanned:
    cmp byte [have_path], 0
    je .use_as_is
    cmp si, path_buffer
    je .use_as_is
    cmp byte [si-1], '\'
    je .directory_operand
    cmp byte [si-1], '/'
    je .directory_operand
    mov dx, path_buffer
    mov cx, 0010h
    mov ah, 4Eh
    int 21h
    jc .use_as_is
    test byte [dta+15h], 10h
    jz .use_as_is
.directory_operand:
    mov si, path_buffer
    mov di, search_buffer
.copy_dir:
    lodsb
    stosb
    or al, al
    jnz .copy_dir
    dec di
    cmp di, search_buffer
    je .append_mask
    cmp byte [di-1], '\'
    je .append_mask
    cmp byte [di-1], '/'
    je .append_mask
    mov byte [di], '\'
    inc di
.append_mask:
    mov si, all_files_mask
.append_mask_loop:
    lodsb
    stosb
    or al, al
    jnz .append_mask_loop
    clc
    jmp .prepare_done
.use_as_is:
    mov si, path_buffer
    cmp byte [have_path], 0
    jne .copy_pattern
    mov si, all_files_mask
.copy_pattern:
    mov di, search_buffer
.copy_pattern_loop:
    lodsb
    stosb
    or al, al
    jnz .copy_pattern_loop
    clc
.prepare_done:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; AUTO is active only when DOS reports stdout as a character device.
resolve_color_mode:
    mov ax, 4400h
    mov bx, 1
    int 21h
    jc .not_console
    test dx, 0080h
    jz .not_console
    mov byte [stdout_console], 1
    jmp .resolve_modes
.not_console:
    mov byte [stdout_console], 0
.resolve_modes:
    cmp byte [color_mode], 2
    jne .resolve_columns
    cmp byte [stdout_console], 0
    je .disable_color
    mov byte [color_mode], 1
    jmp .resolve_columns
.disable_color:
    mov byte [color_mode], 0
 .resolve_columns:
    cmp byte [column_mode], 2
    jne .color_mode_done
    mov al, [stdout_console]
    mov [column_mode], al
.color_mode_done:
    ret

; CF means skip: hide hidden/system entries by default and omit volume labels.
should_print_entry:
    mov al, [dta+15h]
    test al, 08h
    jnz .skip
    cmp byte [show_all], 0
    jne .check_dot
    test al, 06h
    jnz .skip
.check_dot:
    cmp byte [show_dots], 0
    jne .keep
    cmp byte [dta+1Eh], '.'
    jne .keep
    cmp byte [dta+1Fh], 0
    je .skip
    cmp byte [dta+1Fh], '.'
    jne .keep
    cmp byte [dta+20h], 0
    je .skip
.keep:
    clc
    ret
.skip:
    stc
    ret

; Arrange short-format output in fixed 80-column, column-major layout.
display_columns:
    mov word [display_index], 0
    mov word [max_entry_width], 0
.measure_next:
    mov ax, [display_index]
    cmp ax, [entry_count]
    jae .measure_done
    call load_display_entry
    call measure_entry_width
    cmp ax, [max_entry_width]
    jbe .measure_keep
    mov [max_entry_width], ax
.measure_keep:
    inc word [display_index]
    jmp .measure_next
.measure_done:
    mov ax, [max_entry_width]
    add ax, 2
    mov [column_width], ax
    mov bx, ax
    mov ax, 80
    xor dx, dx
    div bx
    or ax, ax
    jnz .columns_nonzero
    mov ax, 1
.columns_nonzero:
    cmp ax, [entry_count]
    jbe .columns_ready
    mov ax, [entry_count]
.columns_ready:
    mov [column_count], ax
    mov bx, ax
    mov ax, [entry_count]
    add ax, bx
    dec ax
    xor dx, dx
    div bx
    mov [column_rows], ax
    mov word [column_row], 0
.row_loop:
    mov ax, [column_row]
    cmp ax, [column_rows]
    jae .done
    mov word [column_index], 0
.column_loop:
    mov ax, [column_index]
    cmp ax, [column_count]
    jae .end_row
    mov bx, [column_rows]
    mul bx
    add ax, [column_row]
    cmp ax, [entry_count]
    jae .end_row
    mov [display_index], ax
    call load_display_entry
    call measure_entry_width
    mov [entry_width], ax
    mov byte [column_output], 1
    call print_entry
    mov byte [column_output], 0

    mov ax, [column_index]
    inc ax
    cmp ax, [column_count]
    jae .end_row
    mov bx, [column_rows]
    mul bx
    add ax, [column_row]
    cmp ax, [entry_count]
    jae .end_row

    mov cx, [column_width]
    sub cx, [entry_width]
.pad_entry:
    jcxz .next_column
    mov al, ' '
    call print_char
    loop .pad_entry
.next_column:
    inc word [column_index]
    jmp .column_loop
.end_row:
    mov dx, crlf
    call print_dollar_string
    inc word [column_row]
    jmp .row_loop
.done:
    ret

; Load the record selected by display_index into the DOS DTA.
load_display_entry:
    push ax
    push cx
    push di
    push ds
    pop es
    mov si, sort_table
    mov cx, [display_index]
.find_record:
    jcxz .record_found
    add si, ENTRY_SIZE
    loop .find_record
.record_found:
    push si
    mov di, dta+1Eh
    mov cx, 13
    rep movsb
    pop si
    mov al, [si+13]
    mov [dta+15h], al
    mov ax, [si+14]
    mov [dta+16h], ax
    mov ax, [si+16]
    mov [dta+18h], ax
    mov ax, [si+18]
    mov [dta+1Ah], ax
    mov ax, [si+20]
    mov [dta+1Ch], ax
    pop di
    pop cx
    pop ax
    ret

; Return visible name width, including any -F/-p suffix.
measure_entry_width:
    push bx
    push cx
    push si
    xor cx, cx
    mov si, dta+1Eh
.count_name:
    cmp byte [si], 0
    je .suffix_width
    inc cx
    inc si
    jmp .count_name
.suffix_width:
    test byte [dta+15h], 10h
    jz .maybe_executable_suffix
    cmp byte [slash_directories], 0
    jne .add_suffix
    cmp byte [classify_names], 0
    je .width_done
    jmp .add_suffix
.maybe_executable_suffix:
    cmp byte [classify_names], 0
    je .width_done
    call is_executable
    jnc .width_done
.add_suffix:
    inc cx
.width_done:
    mov ax, cx
    pop si
    pop cx
    pop bx
    ret

save_entry:
    mov ax, [entry_count]
    cmp ax, MAX_ENTRIES
    jae .full
    mov di, sort_table
    mov cx, ax
.find_slot:
    jcxz .slot_ready
    add di, ENTRY_SIZE
    loop .find_slot
.slot_ready:
    mov si, dta+1Eh
    mov cx, 13
    rep movsb
    mov al, [dta+15h]
    stosb
    mov ax, [dta+16h]
    stosw
    mov ax, [dta+18h]
    stosw
    mov ax, [dta+1Ah]
    stosw
    mov ax, [dta+1Ch]
    stosw
    inc word [entry_count]
    clc
    ret
.full:
    stc
    ret

sort_entries:
    cmp byte [unsorted_order], 0
    jne .done
    mov ax, [entry_count]
    cmp ax, 1
    jbe .done
    dec ax
    mov [sort_passes], ax
.outer:
    mov ax, [sort_passes]
    mov [sort_inner], ax
    mov si, sort_table
.inner:
    mov di, si
    add di, ENTRY_SIZE
    call compare_entries
    jnc .keep_order
    push si
    push di
    mov cx, ENTRY_SIZE
.swap_loop:
    mov al, [si]
    mov bl, [di]
    mov [si], bl
    mov [di], al
    inc si
    inc di
    loop .swap_loop
    pop di
    pop si
.keep_order:
    add si, ENTRY_SIZE
    dec word [sort_inner]
    jnz .inner
    dec word [sort_passes]
    jnz .outer
.done:
    ret

; CF means the adjacent records should be swapped.
compare_entries:
    push ax
    push bx
    push cx
    push si
    push di
    cmp byte [sort_mode], 1
    je .compare_time
    cmp byte [sort_mode], 2
    je .compare_size
    jmp .compare_name
.compare_time:
    mov ax, [si+16]
    cmp ax, [di+16]
    jne .descending
    mov ax, [si+14]
    cmp ax, [di+14]
    jne .descending
    jmp .compare_name
.compare_size:
    mov ax, [si+20]
    cmp ax, [di+20]
    jne .descending
    mov ax, [si+18]
    cmp ax, [di+18]
    jne .descending
    jmp .compare_name
.descending:
    jb .left_less
    jmp .left_greater
.left_less:
    cmp byte [reverse_order], 0
    jne .keep
    jmp .swap
.left_greater:
    cmp byte [reverse_order], 0
    jne .swap
    jmp .keep
.compare_name:
    mov cx, 13
.name_loop:
    mov al, [si]
    mov bl, [di]
    cmp al, 'a'
    jb .left_folded
    cmp al, 'z'
    ja .left_folded
    sub al, 20h
.left_folded:
    cmp bl, 'a'
    jb .right_folded
    cmp bl, 'z'
    ja .right_folded
    sub bl, 20h
.right_folded:
    cmp al, bl
    jne .name_difference
    or al, al
    jz .keep
    inc si
    inc di
    loop .name_loop
    jmp .keep
.name_difference:
    jb .name_less
    jmp .name_greater
.name_less:
    cmp byte [reverse_order], 0
    jne .swap
    jmp .keep
.name_greater:
    cmp byte [reverse_order], 0
    jne .keep
    jmp .swap
.keep:
    clc
    jmp .compare_done
.swap:
    stc
.compare_done:
    pop di
    pop si
    pop cx
    pop bx
    pop ax
    ret

print_entry:
    push ax
    push dx
    push si
    cmp byte [long_format], 0
    je .name_only
    mov al, '-'
    test byte [dta+15h], 10h
    jz .type_ready
    mov al, 'd'
.type_ready:
    call print_char
    mov al, ' '
    call print_char
    mov ax, [dta+1Ah]
    mov dx, [dta+1Ch]
    cmp byte [human_size], 0
    jne .human_file_size
    call print_u32
    jmp .size_printed
.human_file_size:
    call print_human_size
.size_printed:
    mov al, ' '
    call print_char
.name_only:
    cmp byte [color_mode], 0
    je .print_name
    call choose_color
.print_name:
    mov si, dta+1Eh
.print_chars:
    lodsb
    or al, al
    jz .name_done
    call print_char
    jmp .print_chars
.name_done:
    cmp byte [color_mode], 0
    je .suffix
    mov dx, color_reset
    call print_dollar_string
.suffix:
    cmp byte [classify_names], 0
    jne .classified
    cmp byte [slash_directories], 0
    je .newline
.classified:
    test byte [dta+15h], 10h
    jz .classify_exec
    cmp byte [slash_directories], 0
    jne .print_directory_slash
    cmp byte [classify_names], 0
    je .newline
.print_directory_slash:
    mov al, '/'
    call print_char
    jmp .newline
.classify_exec:
    cmp byte [classify_names], 0
    je .newline
    call is_executable
    jnc .newline
    mov al, '*'
    call print_char
.newline:
    cmp byte [column_output], 0
    jne .print_done
    mov dx, crlf
    call print_dollar_string
.print_done:
    pop si
    pop dx
    pop ax
    ret

; Print ANSI color selected from the DTA attributes and 8.3 extension.
choose_color:
    test byte [dta+15h], 10h
    jnz .directory
    test byte [dta+15h], 02h
    jnz .hidden
    call is_executable
    jc .executable
    call is_archive
    jc .archive
    ret
.directory:
    mov dx, color_directory
    jmp .emit
.hidden:
    mov dx, color_hidden
    jmp .emit
.executable:
    mov dx, color_executable
    jmp .emit
.archive:
    mov dx, color_archive
.emit:
    call print_dollar_string
    ret

; Print an unsigned DOS file size using rounded-up K/M/G units.
print_human_size:
    push ax
    push bx
    push cx
    push dx
    push si
    mov [number_low], ax
    mov [number_high], dx
    mov byte [human_suffix], 'K'
    mov ax, [number_high]
    or ax, ax
    jnz .scale
    cmp word [number_low], 1024
    jae .scale
    mov dx, 0
    mov ax, [number_low]
    call print_u32
    jmp .human_done
.scale:
    mov ax, [number_high]
    xor dx, dx
    mov bx, 1024
    div bx
    mov [quotient_high], ax
    mov [remainder_word], dx

    mov ax, [remainder_word]
    xor cx, cx
    mov cl, 6
.shift_remainder:
    shl ax, 1
    loop .shift_remainder
    mov bx, [number_low]
    xor cx, cx
    mov cl, 10
.shift_low:
    shr bx, 1
    loop .shift_low
    add ax, bx
    mov [quotient_low], ax
    mov ax, [number_low]
    and ax, 03FFh
    mov [remainder_word], ax

    mov ax, [quotient_low]
    mov [number_low], ax
    mov ax, [quotient_high]
    mov [number_high], ax
    cmp word [number_high], 0
    jne .scale_again
    cmp word [number_low], 1024
    jb .print_units
.scale_again:
    cmp byte [human_suffix], 'K'
    jne .check_megabyte
    mov byte [human_suffix], 'M'
    jmp .scale
.check_megabyte:
    mov byte [human_suffix], 'G'
    jmp .scale
.print_units:
    cmp word [remainder_word], 512
    jb .emit_units
    inc word [number_low]
    cmp word [number_low], 1024
    jb .emit_units
    cmp byte [human_suffix], 'G'
    je .emit_units
    cmp byte [human_suffix], 'K'
    jne .promote_to_gigabytes
    mov byte [human_suffix], 'M'
    jmp .scale
.promote_to_gigabytes:
    mov byte [human_suffix], 'G'
    jmp .scale
.emit_units:
    mov dx, [number_high]
    mov ax, [number_low]
    call print_u32
    mov al, [human_suffix]
    call print_char
.human_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; CF if the extension is EXE, COM, or BAT.
is_executable:
    push ax
    push si
    mov si, dta+1Eh
    call find_extension
    jc .not_exec
    cmp byte [si], 'E'
    je .exe_check
    cmp byte [si], 'C'
    je .com_check
    cmp byte [si], 'B'
    jne .not_exec
    cmp word [si+1], 'TA'
    jne .not_exec
    stc
    jmp .exec_done
.exe_check:
    cmp word [si+1], 'XE'
    jne .not_exec
    stc
    jmp .exec_done
.com_check:
    cmp word [si+1], 'OM'
    jne .not_exec
    stc
    jmp .exec_done
.not_exec:
    clc
.exec_done:
    pop si
    pop ax
    ret

; CF if the extension is ZIP, ARC, or LZH.
is_archive:
    push ax
    push si
    mov si, dta+1Eh
    call find_extension
    jc .not_archive
    cmp byte [si], 'Z'
    je .zip
    cmp byte [si], 'A'
    je .arc
    cmp byte [si], 'L'
    jne .not_archive
    cmp word [si+1], 'ZH'
    jne .not_archive
    stc
    jmp .archive_done
.zip:
    cmp word [si+1], 'IP'
    jne .not_archive
    stc
    jmp .archive_done
.arc:
    cmp word [si+1], 'RC'
    jne .not_archive
    stc
    jmp .archive_done
.not_archive:
    clc
.archive_done:
    pop si
    pop ax
    ret

; Find the first byte after the dot in an 8.3 filename.
; CF if no extension; SI is preserved on failure and points to the extension otherwise.
find_extension:
    push cx
    mov cx, 9
.find_dot:
    cmp byte [si], '.'
    je .found
    cmp byte [si], 0
    je .not_found
    inc si
    loop .find_dot
.not_found:
    stc
    pop cx
    ret
.found:
    inc si
    clc
    pop cx
    ret

; Print DX:AX as an unsigned 32-bit decimal integer.
print_u32:
    push ax
    push bx
    push cx
    push dx
    push si
    mov [number_low], ax
    mov [number_high], dx
    mov di, number_digits+10
    xor cx, cx
    mov bx, 10
    mov ax, [number_low]
    or ax, [number_high]
    jnz .divide
    mov al, '0'
    call print_char
    jmp .number_done
.divide:
    mov ax, [number_high]
    xor dx, dx
    div bx
    mov [quotient_high], ax
    mov [remainder_word], dx

    mov ax, [remainder_word]
    mov ah, al
    xor al, al
    mov al, [number_low+1]
    xor dx, dx
    div bx
    mov [quotient_low+1], al
    mov [remainder_word], dx

    mov ax, [remainder_word]
    mov ah, al
    xor al, al
    mov al, [number_low]
    xor dx, dx
    div bx
    mov [quotient_low], al
    mov [remainder_word], dx

    mov ax, [quotient_high]
    mov [number_high], ax
    mov ax, [quotient_low]
    mov [number_low], ax

    mov ax, [remainder_word]
    add al, '0'
    dec di
    mov [di], al
    inc cx
    mov ax, [number_low]
    or ax, [number_high]
    jnz .divide
.emit_digits:
    mov al, [di]
    call print_char
    inc di
    loop .emit_digits
.number_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_char:
    push ax
    push dx
    mov dl, al
    mov ah, 02h
    int 21h
    pop dx
    pop ax
    cmp al, 0Ah
    jne .done
    cmp byte [stdout_console], 0
    je .done
    inc word [screen_line_count]
    cmp word [screen_line_count], 24
    jb .done
    call pause_for_key
.done:
    ret

pause_for_key:
    push ax
    push cx
    push dx
    mov dx, pause_message
    call print_dollar_string
    xor ah, ah
    int 16h
    mov al, 13
    call print_char
    mov cx, 79
.clear_prompt:
    mov al, ' '
    call print_char
    loop .clear_prompt
    mov al, 13
    call print_char
    mov word [screen_line_count], 0
    pop dx
    pop cx
    pop ax
    ret

; Print a DOS '$'-terminated string at DS:DX.
print_dollar_string:
    push ax
    push dx
    push si
    mov si, dx
.print_next:
    mov al, [si]
    cmp al, '$'
    je .done
    call print_char
    inc si
    jmp .print_next
.done:
    pop si
    pop dx
    pop ax
    ret

usage_message:
    db 'Invalid option or too many paths. Use LS --help.',13,10,'$'
help_message:
    db 'LS for DOS 6.22 (8086/8088)',13,10
    db 'Usage: LS [options] [directory|pattern|file]',13,10
    db 'Help: -help or --help',13,10
    db '  -a       include hidden/system and . / .. entries',13,10
    db '  -A       include hidden/system; omit . / .. entries',13,10
    db '  -l       show directory marker and file size in bytes',13,10
    db '  -h       show rounded K/M/G sizes; implies -l',13,10
    db '  -1       force one entry per line',13,10
    db '  -C       force 80-column multi-column output',13,10
    db '  -F       append / to directories and * to EXE/COM/BAT',13,10
    db '  -p       append / to directories',13,10
    db '  -r       reverse the selected sort order',13,10
    db '  -t       sort newest first',13,10
    db '  -S       sort largest files first',13,10
    db '  -U       keep DOS search order (no sorting)',13,10
    db '  -f       include hidden, unsorted, no color/columns',13,10
    db '  --color       ANSI colors on (default)',13,10
    db '  --color=auto  color only when output is console',13,10
    db '  --color=never disable ANSI colors',13,10
    db 'Short output defaults to columns on console, lines if redirected.',13,10
    db 'Long output pauses every 24 lines on console; press any key.',13,10
    db 'Needs ANSI.SYS for color. DOS 8.3 names; max 512 matches.',13,10,'$'
path_error_message:
    db 'Unable to prepare the requested path.',13,10,'$'
no_matches_message:
    db 'No matching files.',13,10,'$'
too_many_message:
    db 'Too many matches (maximum 512); narrow the pattern.',13,10,'$'
pause_message:
    db 'Press any key to continue...$'
crlf:
    db 13,10,'$'
color_reset:
    db 27,'[0m$'
color_directory:
    db 27,'[1;34m$'
color_hidden:
    db 27,'[1;36m$'
color_executable:
    db 27,'[1;32m$'
color_archive:
    db 27,'[1;35m$'
all_files_mask:
    db '*.*',0

command_buffer:
    times 130 db 0
token_buffer:
    times 130 db 0
path_buffer:
    db '*.*',0
    times 124 db 0
search_buffer:
    times 160 db 0
dta:
    times 43 db 0
number_low:
    dw 0
number_high:
    dw 0
quotient_low:
    dw 0
quotient_high:
    dw 0
remainder_word:
    dw 0
number_digits:
    times 11 db 0

have_path:
    db 0
show_all:
    db 0
show_dots:
    db 0
long_format:
    db 0
classify_names:
    db 0
slash_directories:
    db 0
color_mode:
    db 1
help_flag:
    db 0
token_ended:
    db 0
command_cursor:
    dw 0
human_size:
    db 0
reverse_order:
    db 0
sort_mode:
    db 0
unsorted_order:
    db 0
human_suffix:
    db 'K'
entry_count:
    dw 0
display_index:
    dw 0
sort_passes:
    dw 0
sort_inner:
    dw 0
stdout_console:
    db 0
column_mode:
    db 2
column_output:
    db 0
max_entry_width:
    dw 0
column_width:
    dw 0
column_count:
    dw 0
column_rows:
    dw 0
column_row:
    dw 0
column_index:
    dw 0
entry_width:
    dw 0
screen_line_count:
    dw 0

sort_table:
    times MAX_ENTRIES*ENTRY_SIZE db 0
stack_space:
    times 1024 db 0
stack_top:
