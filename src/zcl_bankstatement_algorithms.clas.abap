*&---------------------------------------------------------------------*
*& Clase ZCL_BANKSTATEMENT_ALGORITHMS - Determinación de BP en concepto
*&---------------------------------------------------------------------*
*& Busca el business partner en el texto del concepto (memoline) por
*& NIF/CIF/NIE españoles validados contra los tax numbers de BP.
*& NOTA: iv_convert_instrid es un stub y tg_pmtinfo nunca se carga
*& (iv_find_isd no puede resolver): pendientes de implementación si
*& esta clase se llega a integrar en el flujo (hoy sin llamadores).
*&---------------------------------------------------------------------*
CLASS zcl_bankstatement_algorithms DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_bp,
        businesspartner     TYPE i_businesspartner-businesspartner,
        businesspartnername TYPE i_businesspartner-businesspartnername,
        bptaxtype           TYPE i_businesspartnertaxnumber-bptaxtype,
        bptaxnumber         TYPE i_businesspartnertaxnumber-bptaxnumber,
      END OF ty_bp,
      tty_bp TYPE STANDARD TABLE OF ty_bp.

    " Buffer ordenado por clave fiscal: búsqueda binaria implícita sin copias
    TYPES tty_bp_sorted TYPE SORTED TABLE OF ty_bp
                        WITH NON-UNIQUE KEY bptaxtype bptaxnumber.

    TYPES:
      BEGIN OF ty_search_payminfo,
        swiftcode     TYPE swift,
        external_code TYPE c LENGTH 20,
        sign          TYPE c LENGTH 1,
      END OF ty_search_payminfo,
      tty_search_payminfo TYPE STANDARD TABLE OF ty_search_payminfo.

    TYPES:
      BEGIN OF ty_notetopayee,
        alg_id     TYPE i,
        alg_txt    TYPE c LENGTH 30,
        alg_result TYPE c LENGTH 65,
      END OF ty_notetopayee,
      tty_notetopayee TYPE STANDARD TABLE OF ty_notetopayee WITH EMPTY KEY.

    TYPES: BEGIN OF ty_numbers,
             number    TYPE c LENGTH 13,
             relevance TYPE i,
           END OF ty_numbers,
           tty_numbers TYPE STANDARD TABLE OF ty_numbers.

    TYPES ty_checknumber           TYPE c LENGTH 13.
    TYPES ty_es_taxid_length       TYPE c LENGTH 9.
    TYPES ty_paymentdocumentnumber TYPE belnr_d.

    CLASS-DATA tg_businesspartnertaxnumber TYPE tty_bp_sorted.
    CLASS-DATA tg_pmtinfo                  TYPE tty_search_payminfo.

    "! <p class="shorttext synchronized" lang="es">Ejecuta los algoritmos sobre el concepto</p>
    CLASS-METHODS ip_process_algorithms
      IMPORTING
        ip_companycode     TYPE bukrs
        is_febep           TYPE zr_febp
        iv_memoline        TYPE string
        is_pmtinfo         TYPE ty_search_payminfo
      EXPORTING
        ev_businesspartner TYPE i_businesspartner-businesspartner
        et_notetopayee     TYPE tty_notetopayee.

  PRIVATE SECTION.
    CONSTANTS:
      c_es1_cif_pattern TYPE string VALUE '[A-Z]\d{7}[A-Z0-9]',
      c_es1_nif_pattern TYPE string VALUE '\d{8}[A-Z]',
      c_es1_nie_pattern TYPE string VALUE '[XYZ]\d{7}[A-Z]',
      c_es1_check_letra TYPE string VALUE 'TRWAGMYFPDXBNJZSQVHLCKE'.

    CONSTANTS:
      c_max_nums      TYPE i      VALUE 10,
      c_left2right    TYPE i      VALUE 0,
      c_right2left    TYPE i      VALUE 1,
      c_numbers_chars TYPE string VALUE '0123456789',
      c_zero_char     TYPE string VALUE '0'.

    " Carga perezosa del buffer de tax numbers (evita cargar TODOS los BP
    " del tenant al primer toque de la clase, como hacía class_constructor)
    CLASS-DATA gv_buffers_loaded TYPE abap_bool.

    CLASS-METHODS ensure_buffers_loaded.

    CLASS-METHODS iv_alg_001_busq_bp
      IMPORTING
        iv_memoline        TYPE string
      EXPORTING
        ev_businesspartner TYPE i_businesspartner-businesspartner.

    CLASS-METHODS iv_alg_001_es
      IMPORTING
        iv_memoline        TYPE string
      EXPORTING
        ev_businesspartner TYPE i_businesspartner-businesspartner.

    CLASS-METHODS iv_find_isd
      IMPORTING
        iv_string           TYPE string
        ip_companycode      TYPE bukrs
        is_pmtinfo          TYPE ty_search_payminfo
      RETURNING
        VALUE(rv_isdnumber) TYPE ty_checknumber.

    CLASS-METHODS iv_convert_instrid
      IMPORTING
        iv_string      TYPE string
        ip_companycode TYPE bukrs
        is_pmtinfo     TYPE ty_search_payminfo
      EXPORTING
        ev_paymdocnum  TYPE ty_paymentdocumentnumber
        ev_paymbatchid TYPE string
        ev_bp          TYPE bp_partner.

    CLASS-METHODS iv_find_numbers_in_string
      IMPORTING
        iv_string     TYPE string
        iv_max_length TYPE i
      CHANGING
        ct_numbers    TYPE tty_numbers.

    CLASS-METHODS iv_move_number_to_strings
      IMPORTING
        iv_max_length    TYPE i
        iv_add_relevance TYPE i
      CHANGING
        cv_num_string    TYPE string
        ct_numbers_list  TYPE tty_numbers.

    CLASS-METHODS iv_validate_cif
      IMPORTING iv_cif          TYPE ty_es_taxid_length
      RETURNING VALUE(rv_valid) TYPE abap_boolean.

    CLASS-METHODS iv_validate_nif
      IMPORTING iv_nif          TYPE ty_es_taxid_length
      RETURNING VALUE(rv_valid) TYPE abap_boolean.

    CLASS-METHODS iv_validate_nie
      IMPORTING iv_nie          TYPE ty_es_taxid_length
      RETURNING VALUE(rv_valid) TYPE abap_boolean.

ENDCLASS.



CLASS ZCL_BANKSTATEMENT_ALGORITHMS IMPLEMENTATION.


  METHOD iv_alg_001_es.
    DATA: tl_cif_results TYPE match_result_tab,
          tl_nif_results TYPE match_result_tab,
          tl_nie_results TYPE match_result_tab.

    DATA wl_tax_id_es TYPE ty_es_taxid_length.

    ensure_buffers_loaded( ).

    FIND ALL OCCURRENCES OF PCRE c_es1_cif_pattern IN iv_memoline RESULTS tl_cif_results.
    FIND ALL OCCURRENCES OF PCRE c_es1_nif_pattern IN iv_memoline RESULTS tl_nif_results.
    FIND ALL OCCURRENCES OF PCRE c_es1_nie_pattern IN iv_memoline RESULTS tl_nie_results.

    " Nota: offset 0 es un match válido (identificador al inicio del texto)
    LOOP AT tl_cif_results INTO DATA(xl_cif_result).
      CHECK xl_cif_result-length = 9.
      CHECK strlen( iv_memoline ) >= xl_cif_result-offset + xl_cif_result-length.

      wl_tax_id_es = substring( val = iv_memoline
                                off = xl_cif_result-offset
                                len = xl_cif_result-length ).

      IF iv_validate_cif( wl_tax_id_es ) = abap_true.
        READ TABLE tg_businesspartnertaxnumber INTO DATA(xl_bptax)
          WITH KEY bptaxtype   = 'ES1'
                   bptaxnumber = wl_tax_id_es.

        IF sy-subrc = 0.
          ev_businesspartner = xl_bptax-businesspartner.
          RETURN.
        ELSE.
          READ TABLE tg_businesspartnertaxnumber INTO xl_bptax
            WITH KEY bptaxtype   = 'ES0'
                     bptaxnumber = |ES{ wl_tax_id_es }|.

          IF sy-subrc = 0.
            ev_businesspartner = xl_bptax-businesspartner.
            RETURN.
          ENDIF.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF ev_businesspartner IS INITIAL.
      LOOP AT tl_nif_results INTO DATA(xl_nif_result).
        CHECK xl_nif_result-length = 9.
        CHECK strlen( iv_memoline ) >= xl_nif_result-offset + xl_nif_result-length.

        wl_tax_id_es = substring( val = iv_memoline
                                  off = xl_nif_result-offset
                                  len = xl_nif_result-length ).

        IF iv_validate_nif( wl_tax_id_es ) = abap_true.
          READ TABLE tg_businesspartnertaxnumber INTO xl_bptax
            WITH KEY bptaxtype   = 'ES1'
                     bptaxnumber = wl_tax_id_es.

          IF sy-subrc = 0.
            ev_businesspartner = xl_bptax-businesspartner.
            RETURN.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.

    IF ev_businesspartner IS INITIAL.
      LOOP AT tl_nie_results INTO DATA(xl_nie_result).
        CHECK xl_nie_result-length = 9.
        CHECK strlen( iv_memoline ) >= xl_nie_result-offset + xl_nie_result-length.

        wl_tax_id_es = substring( val = iv_memoline
                                  off = xl_nie_result-offset
                                  len = xl_nie_result-length ).

        IF iv_validate_nie( wl_tax_id_es ) = abap_true.
          READ TABLE tg_businesspartnertaxnumber INTO xl_bptax
            WITH KEY bptaxtype   = 'ES1'
                     bptaxnumber = wl_tax_id_es.

          IF sy-subrc = 0.
            ev_businesspartner = xl_bptax-businesspartner.
            RETURN.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.


  METHOD iv_convert_instrid.
    " STUB pendiente de implementación (resolución de InstrId a documento
    " de pago). Devuelve vacío deliberadamente.
    CLEAR: ev_paymdocnum, ev_paymbatchid, ev_bp.
  ENDMETHOD.


  METHOD iv_find_isd.
    DATA tl_numbers TYPE tty_numbers.

    CLEAR rv_isdnumber.

    " tg_pmtinfo no se carga en ningún punto: sin registro no hay búsqueda
    " (pendiente de implementación si se integra esta clase)
    READ TABLE tg_pmtinfo TRANSPORTING NO FIELDS
      WITH KEY swiftcode     = is_pmtinfo-swiftcode
               external_code = is_pmtinfo-external_code.

    CHECK sy-subrc = 0.

    iv_find_numbers_in_string(
      EXPORTING iv_string     = iv_string
                iv_max_length = 10
      CHANGING  ct_numbers    = tl_numbers ).

    DELETE tl_numbers WHERE number IS INITIAL
                         OR number(1) <> '1'
                         OR relevance <> 0.

    IF lines( tl_numbers ) = 1.
      rv_isdnumber = tl_numbers[ 1 ]-number.
    ENDIF.
  ENDMETHOD.


  METHOD iv_validate_nif.
    DATA: wl_nif_num TYPE n LENGTH 8,
          wl_resto   TYPE i.

    rv_valid = abap_false.
    CHECK strlen( iv_nif ) = 9.

    TRY.
        wl_nif_num = iv_nif(8).
      CATCH cx_sy_conversion_no_number cx_sy_range_out_of_bounds.
        RETURN.
    ENDTRY.

    wl_resto = wl_nif_num MOD 23.
    CHECK wl_resto >= 0 AND wl_resto < strlen( c_es1_check_letra ).

    TRY.
        IF c_es1_check_letra+wl_resto(1) = iv_nif+8(1).
          rv_valid = abap_true.
        ENDIF.
      CATCH cx_sy_range_out_of_bounds.
        RETURN.
    ENDTRY.
  ENDMETHOD.


  METHOD ensure_buffers_loaded.
    IF gv_buffers_loaded = abap_true.
      RETURN.
    ENDIF.

    SELECT b~businesspartner,
           b~businesspartnername,
           a~bptaxtype,
           a~bptaxnumber
      FROM i_businesspartnertaxnumber WITH PRIVILEGED ACCESS AS a
      INNER JOIN i_businesspartner WITH PRIVILEGED ACCESS AS b
        ON b~businesspartner = a~businesspartner
      INTO TABLE @tg_businesspartnertaxnumber.

    gv_buffers_loaded = abap_true.
  ENDMETHOD.


  METHOD iv_find_numbers_in_string.
    CONSTANTS:
      c_convert1 TYPE c LENGTH 52 VALUE 'A B C D E F G H I J K L M N O P Q R S T U V W X Y Z ',
      c_convert2 TYPE c LENGTH 52 VALUE '. , < > & " % ! ( ) = ? : - # * + / $ # _ ; '.

    DATA: wl_string     TYPE string,
          wl_str2num    TYPE string,
          wl_char       TYPE c LENGTH 1,
          wl_strlen     TYPE i,
          wl_index      TYPE i,
          wl_max_length TYPE i.

    CHECK iv_string IS NOT INITIAL.

    wl_string = to_upper( iv_string ).
    TRANSLATE wl_string USING c_convert1.
    TRANSLATE wl_string USING c_convert2.

    wl_max_length = COND #( WHEN iv_max_length IS NOT INITIAL
                            THEN iv_max_length
                            ELSE c_max_nums ).

    wl_strlen = strlen( wl_string ).
    CLEAR: wl_char, wl_index, wl_str2num.

    " Barrido izquierda->derecha
    DO wl_strlen TIMES.
      wl_char = wl_string+wl_index(1).

      IF wl_char CO c_numbers_chars.
        wl_str2num = wl_str2num && wl_char.

        IF strlen( wl_str2num ) = wl_max_length.
          iv_move_number_to_strings(
            EXPORTING iv_max_length    = iv_max_length
                      iv_add_relevance = c_left2right
            CHANGING  cv_num_string    = wl_str2num
                      ct_numbers_list  = ct_numbers ).
        ENDIF.
      ELSEIF wl_str2num IS NOT INITIAL.
        iv_move_number_to_strings(
          EXPORTING iv_max_length    = iv_max_length
                    iv_add_relevance = c_left2right
          CHANGING  cv_num_string    = wl_str2num
                    ct_numbers_list  = ct_numbers ).
      ENDIF.

      wl_index += 1.
    ENDDO.

    IF wl_str2num IS NOT INITIAL.
      iv_move_number_to_strings(
        EXPORTING iv_max_length    = iv_max_length
                  iv_add_relevance = c_left2right
        CHANGING  cv_num_string    = wl_str2num
                  ct_numbers_list  = ct_numbers ).
    ENDIF.

    " Barrido derecha->izquierda
    wl_index = wl_strlen - 1.
    CLEAR wl_str2num.

    DO wl_strlen TIMES.
      wl_char = wl_string+wl_index(1).

      IF wl_char CO c_numbers_chars.
        wl_str2num = wl_char && wl_str2num.

        IF strlen( wl_str2num ) = wl_max_length.
          iv_move_number_to_strings(
            EXPORTING iv_max_length    = iv_max_length
                      iv_add_relevance = c_right2left
            CHANGING  cv_num_string    = wl_str2num
                      ct_numbers_list  = ct_numbers ).
        ENDIF.
      ELSEIF wl_str2num IS NOT INITIAL.
        iv_move_number_to_strings(
          EXPORTING iv_max_length    = iv_max_length
                    iv_add_relevance = c_right2left
          CHANGING  cv_num_string    = wl_str2num
                    ct_numbers_list  = ct_numbers ).
      ENDIF.

      wl_index -= 1.
    ENDDO.

    IF wl_str2num IS NOT INITIAL.
      iv_move_number_to_strings(
        EXPORTING iv_max_length    = iv_max_length
                  iv_add_relevance = c_right2left
        CHANGING  cv_num_string    = wl_str2num
                  ct_numbers_list  = ct_numbers ).
    ENDIF.

    SORT ct_numbers BY relevance ASCENDING.
  ENDMETHOD.


  METHOD iv_move_number_to_strings.
    DATA xl_number_in_list LIKE LINE OF ct_numbers_list.

    CHECK cv_num_string IS NOT INITIAL.

    TRY.
        xl_number_in_list-number    = cv_num_string.
        xl_number_in_list-relevance = iv_max_length - strlen( cv_num_string ) + iv_add_relevance.

        IF NOT cv_num_string CO c_zero_char AND
           NOT line_exists( ct_numbers_list[ number = xl_number_in_list-number ] ).
          APPEND xl_number_in_list TO ct_numbers_list.
        ENDIF.

        CLEAR cv_num_string.

      CATCH cx_sy_conversion_no_number.
        CLEAR cv_num_string.
    ENDTRY.
  ENDMETHOD.


  METHOD iv_validate_cif.
    DATA: wl_cifdigits   TYPE c LENGTH 7,
          wl_sum_pairs   TYPE i,
          wl_sum_impair  TYPE i,
          wl_sum_total   TYPE i,
          wl_unidades    TYPE i,
          wl_d           TYPE i,
          wl_check_digit TYPE c LENGTH 1.

    rv_valid = abap_false.
    CHECK strlen( iv_cif ) = 9.

    DATA(wl_first_letter) = iv_cif(1).
    CHECK wl_first_letter CA 'ABCDEFGHJNPQRSUVW'.

    TRY.
        wl_cifdigits = iv_cif+1(7).
      CATCH cx_sy_range_out_of_bounds.
        RETURN.
    ENDTRY.

    CHECK wl_cifdigits CO '0123456789'.

    TRY.
        wl_sum_pairs = CONV i( wl_cifdigits+1(1) ) +
                       CONV i( wl_cifdigits+3(1) ) +
                       CONV i( wl_cifdigits+5(1) ).
      CATCH cx_sy_conversion_no_number cx_sy_range_out_of_bounds.
        RETURN.
    ENDTRY.

    DO 4 TIMES.
      DATA(wl_idx) = ( sy-index - 1 ) * 2.
      TRY.
          DATA(wl_digit) = CONV i( wl_cifdigits+wl_idx(1) ).
          DATA(wl_double) = wl_digit * 2.
          wl_sum_impair += ( wl_double MOD 10 ) + ( wl_double DIV 10 ).
        CATCH cx_sy_conversion_no_number cx_sy_range_out_of_bounds.
          RETURN.
      ENDTRY.
    ENDDO.

    wl_sum_total = wl_sum_pairs + wl_sum_impair.
    wl_unidades = wl_sum_total MOD 10.
    wl_d = ( 10 - wl_unidades ) MOD 10.

    wl_check_digit = iv_cif+8(1).

    IF wl_first_letter CA 'KPQS'.
      IF wl_check_digit = wl_d.
        rv_valid = abap_true.
      ENDIF.
    ELSE.
      IF wl_check_digit = wl_d.
        rv_valid = abap_true.
      ELSEIF wl_d < 10.
        DATA(wl_expected_letter) = SWITCH #( wl_d
          WHEN 0 THEN 'J'
          WHEN 1 THEN 'A'
          WHEN 2 THEN 'B'
          WHEN 3 THEN 'C'
          WHEN 4 THEN 'D'
          WHEN 5 THEN 'E'
          WHEN 6 THEN 'F'
          WHEN 7 THEN 'G'
          WHEN 8 THEN 'H'
          WHEN 9 THEN 'I'
          ELSE space ).

        IF wl_check_digit = wl_expected_letter.
          rv_valid = abap_true.
        ENDIF.
      ENDIF.
    ENDIF.
  ENDMETHOD.


  METHOD iv_validate_nie.
    DATA: wl_nie_num TYPE n LENGTH 8,
          wl_resto   TYPE i.

    rv_valid = abap_false.

    CHECK strlen( iv_nie ) = 9.
    CHECK iv_nie(1) CA 'XYZ'.

    DATA(wl_prefix) = SWITCH string( iv_nie(1)
      WHEN 'X' THEN '0'
      WHEN 'Y' THEN '1'
      WHEN 'Z' THEN '2'
      ELSE space ).

    CHECK wl_prefix IS NOT INITIAL.

    TRY.
        DATA(wl_middle_digits) = iv_nie+1(7).
        wl_nie_num = |{ wl_prefix }{ wl_middle_digits }|.
      CATCH cx_sy_conversion_no_number cx_sy_range_out_of_bounds.
        RETURN.
    ENDTRY.

    wl_resto = wl_nie_num MOD 23.
    CHECK wl_resto >= 0 AND wl_resto < strlen( c_es1_check_letra ).

    TRY.
        IF c_es1_check_letra+wl_resto(1) = iv_nie+8(1).
          rv_valid = abap_true.
        ENDIF.
      CATCH cx_sy_range_out_of_bounds.
        RETURN.
    ENDTRY.
  ENDMETHOD.


  METHOD iv_alg_001_busq_bp.
    iv_alg_001_es(
      EXPORTING iv_memoline        = iv_memoline
      IMPORTING ev_businesspartner = ev_businesspartner ).
  ENDMETHOD.


  METHOD ip_process_algorithms.
    DATA: wl_paymdocnum  TYPE ty_paymentdocumentnumber,
          wl_paymbatchid TYPE string,
          wl_isdnumber   TYPE ty_checknumber.

    CLEAR: ev_businesspartner, et_notetopayee.

    ensure_buffers_loaded( ).

    iv_convert_instrid(
      EXPORTING iv_string      = iv_memoline
                ip_companycode = ip_companycode
                is_pmtinfo     = is_pmtinfo
      IMPORTING ev_paymdocnum  = wl_paymdocnum
                ev_paymbatchid = wl_paymbatchid
                ev_bp          = ev_businesspartner ).

    IF wl_paymdocnum IS NOT INITIAL.
      APPEND VALUE #(
        alg_id     = 3
        alg_txt    = '#  InstrId: '
        alg_result = wl_paymdocnum
      ) TO et_notetopayee.
    ENDIF.

    wl_isdnumber = iv_find_isd(
      iv_string      = iv_memoline
      ip_companycode = ip_companycode
      is_pmtinfo     = is_pmtinfo ).

    IF wl_isdnumber IS NOT INITIAL.
      APPEND VALUE #(
        alg_id     = 2
        alg_txt    = COND #( WHEN wl_paymdocnum IS NOT INITIAL
                             THEN '#  PmtInfId: '
                             ELSE '#  MsgId: ' )
        alg_result = COND #( WHEN wl_paymdocnum IS NOT INITIAL
                             THEN |0{ wl_isdnumber }|
                             ELSE wl_isdnumber )
      ) TO et_notetopayee.
    ENDIF.

    IF ev_businesspartner IS INITIAL.
      iv_alg_001_busq_bp(
        EXPORTING iv_memoline        = iv_memoline
        IMPORTING ev_businesspartner = ev_businesspartner ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
