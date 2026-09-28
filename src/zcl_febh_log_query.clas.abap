"! <p class="shorttext synchronized" lang="es">Query provider del log del extracto</p>
"! Sirve la custom entity <em>ZC_FEBH_LOG</em>: relee el BALI del extracto
"! filtrando por <em>external_id = FebhUUID</em> (referencia única) para que
"! cada extracto vea SOLO su propio log en la Object Page.
CLASS zcl_febh_log_query DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_rap_query_provider.

  PRIVATE SECTION.
    " Estructura espejo de ZC_FEBH_LOG (tipos locales para evitar la
    " dependencia circular entidad <-> clase en la generación)
    TYPES: BEGIN OF ty_log_row,
             febhuuid            TYPE sysuuid_x16,
             sequence            TYPE i,
             severity            TYPE c LENGTH 1,
             severitycriticality TYPE i,
             message             TYPE c LENGTH 250,
           END OF ty_log_row,
           tt_log_row TYPE STANDARD TABLE OF ty_log_row WITH DEFAULT KEY.
ENDCLASS.



CLASS ZCL_FEBH_LOG_QUERY IMPLEMENTATION.


  METHOD if_rap_query_provider~select.
    DATA lt_result TYPE tt_log_row.
    DATA lv_uuid   TYPE sysuuid_x16.

    " 1. Filtro por FebhUUID (referencia única = external_id del BALI)
    TRY.
        DATA(lt_ranges) = io_request->get_filter( )->get_as_ranges( ).
      CATCH cx_rap_query_filter_no_range.
        IF 1 = 2.
        ENDIF.
    ENDTRY.

    LOOP AT lt_ranges INTO DATA(ls_pair) WHERE name = 'FEBHUUID'.
      READ TABLE ls_pair-range INTO DATA(ls_range) INDEX 1.
      IF sy-subrc = 0.
        lv_uuid = ls_range-low.
      ENDIF.
    ENDLOOP.

    " 2. Releer el log BALI de ese extracto
    IF lv_uuid IS NOT INITIAL.
      DATA(lt_rows) = zcl_bankstatement_applog=>read_statement_log( lv_uuid ).
      lt_result = VALUE #( FOR r IN lt_rows
                           ( febhuuid            = lv_uuid
                             sequence            = r-sequence
                             severity            = r-severity
                             severitycriticality = r-criticality
                             message             = r-message ) ).
    ENDIF.

    " 3. Consumir sort + paging (offset/page_size = INT8, contrato obligatorio)
    io_request->get_sort_elements( ).
    DATA(lo_paging)    = io_request->get_paging( ).
    DATA(lv_offset)    = lo_paging->get_offset( ).
    DATA(lv_page_size) = lo_paging->get_page_size( ).

    DATA(lv_total) = lines( lt_result ).

    IF lv_offset > 0.
      DELETE lt_result TO CONV i( lv_offset ).
    ENDIF.
    IF lv_page_size <> if_rap_query_paging=>page_size_unlimited
       AND lv_page_size < lines( lt_result ).
      DELETE lt_result FROM CONV i( lv_page_size ) + 1.
    ENDIF.

    " 4. Total + data SIEMPRE (fuera de cualquier TRY)
    IF io_request->is_total_numb_of_rec_requested( ).
      io_response->set_total_number_of_records( CONV int8( lv_total ) ).
    ENDIF.
    io_response->set_data( lt_result ).
  ENDMETHOD.
ENDCLASS.
