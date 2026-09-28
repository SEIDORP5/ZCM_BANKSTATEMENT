"! <p class="shorttext synchronized" lang="es">Log BALI por extracto bancario</p>
"! Escribe y relee el log de aplicación de un extracto usando como
"! <strong>referencia única</strong> el UUID del registro (<em>external_id</em>
"! del BALI). Así cada extracto del monitor ve SOLO su propio log.
"! Objeto de log: <em>ZAL_BANKSTATEMENT</em> / <em>ZALS_BANKSTATEMENT</em>.
CLASS zcl_bankstatement_applog DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_message,
             severity TYPE c LENGTH 1, " E/W/S/I
             text     TYPE string,
           END OF ty_message,
           tt_message TYPE STANDARD TABLE OF ty_message WITH EMPTY KEY.

    TYPES: BEGIN OF ty_log_row,
             sequence    TYPE i,
             severity    TYPE c LENGTH 1,
             criticality TYPE i,
             message     TYPE c LENGTH 250,
           END OF ty_log_row,
           tt_log_row TYPE STANDARD TABLE OF ty_log_row WITH DEFAULT KEY.

    "! <p class="shorttext synchronized" lang="es">Escribe mensajes en el BALI del extracto</p>
    CLASS-METHODS log_statement_messages
      IMPORTING iv_statement_uuid TYPE sysuuid_x16
                it_messages       TYPE tt_message.

    "! <p class="shorttext synchronized" lang="es">Relee el log BALI del extracto</p>
    CLASS-METHODS read_statement_log
      IMPORTING iv_statement_uuid TYPE sysuuid_x16
      RETURNING VALUE(rt_rows)    TYPE tt_log_row.

  PRIVATE SECTION.
    CONSTANTS c_object    TYPE balobj_d  VALUE 'ZAL_BANKSTATEMENT'.
    CONSTANTS c_subobject TYPE balsubobj VALUE 'ZALS_BANKSTATEMENT'.

    CLASS-METHODS map_severity
      IMPORTING iv_severity   TYPE ty_message-severity
      RETURNING VALUE(rv_sev) LIKE if_bali_constants=>c_severity_status.
ENDCLASS.



CLASS ZCL_BANKSTATEMENT_APPLOG IMPLEMENTATION.


  METHOD log_statement_messages.
    IF it_messages IS INITIAL OR iv_statement_uuid IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        DATA(lo_log) = cl_bali_log=>create_with_header(
          header = cl_bali_header_setter=>create( object      = c_object
                                                  subobject   = c_subobject
                                                  external_id = CONV #( iv_statement_uuid ) ) ).

        LOOP AT it_messages INTO DATA(xl_msg).
          DATA(lo_item) = cl_bali_free_text_setter=>create(
                              severity = map_severity( xl_msg-severity )
                              text     = CONV #( xl_msg-text ) ).
          lo_log->add_item( item = lo_item ).
        ENDLOOP.

        " Conexión secundaria: el log sobrevive aunque la LUW principal haga ROLLBACK
        cl_bali_log_db=>get_instance( )->save_log_2nd_db_connection( log = lo_log ).
      CATCH cx_bali_runtime.
        " Best-effort: el log nunca debe tumbar el proceso del extracto
        IF 1 = 2.
        ENDIF.
    ENDTRY.
  ENDMETHOD.


  METHOD read_statement_log.
    DATA lv_seq TYPE i.

    TRY.
        DATA(lo_filter) = cl_bali_log_filter=>create( )->set_descriptor(
                              object      = c_object
                              external_id = CONV #( iv_statement_uuid ) ).

        DATA(lt_logs) = cl_bali_log_db=>get_instance( )->load_logs_w_items_via_filter( lo_filter ).

        LOOP AT lt_logs INTO DATA(lo_log).
          LOOP AT lo_log->get_all_items( ) INTO DATA(ls_item).
            lv_seq += 1.
            DATA(lv_sev) = ls_item-item->severity.
            APPEND VALUE #(
              sequence    = lv_seq
              severity    = SWITCH #( lv_sev
                              WHEN if_bali_constants=>c_severity_error   THEN 'E'
                              WHEN if_bali_constants=>c_severity_warning THEN 'W'
                              WHEN if_bali_constants=>c_severity_status  THEN 'S'
                              ELSE                                            'I' )
              criticality = SWITCH #( lv_sev
                              WHEN if_bali_constants=>c_severity_error   THEN 1
                              WHEN if_bali_constants=>c_severity_warning THEN 2
                              WHEN if_bali_constants=>c_severity_status  THEN 3
                              ELSE                                            0 )
              message     = CONV #( ls_item-item->get_message_text( ) ) ) TO rt_rows.
          ENDLOOP.
        ENDLOOP.
      CATCH cx_bali_runtime cx_root.
        " Sin autorización S_APPL_LOG o sin log: devolver vacío, sin dump
        IF 1 = 2.
        ENDIF.
    ENDTRY.
  ENDMETHOD.


  METHOD map_severity.
    rv_sev = SWITCH #( iv_severity
               WHEN 'E' OR 'A' THEN if_bali_constants=>c_severity_error
               WHEN 'W'        THEN if_bali_constants=>c_severity_warning
               WHEN 'S'        THEN if_bali_constants=>c_severity_status
               ELSE                 if_bali_constants=>c_severity_information ).
  ENDMETHOD.
ENDCLASS.
