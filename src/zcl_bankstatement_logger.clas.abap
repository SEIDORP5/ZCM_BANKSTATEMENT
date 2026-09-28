*&---------------------------------------------------------------------*
*& Clase ZCL_BANKSTATEMENT_LOGGER - Log centralizado del motor
*&---------------------------------------------------------------------*
*& Acumula la traza en memoria y, además, bufferiza los mensajes por
*& extracto (UUID en curso fijado con ip_set_statement) para persistirlos
*& en BALI con external_id = UUID del extracto (ip_flush_to_bali).
*& Cada extracto del monitor ve así SOLO su propio log en Fiori.
*&---------------------------------------------------------------------*
CLASS zcl_bankstatement_logger DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! <p class="shorttext synchronized" lang="es">Registra un mensaje informativo</p>
    METHODS ip_log_info
      IMPORTING iv_message TYPE string.

    "! <p class="shorttext synchronized" lang="es">Registra un aviso</p>
    METHODS ip_log_warning
      IMPORTING iv_message TYPE string.

    "! <p class="shorttext synchronized" lang="es">Registra un error</p>
    METHODS ip_log_error
      IMPORTING iv_message TYPE string.

    "! <p class="shorttext synchronized" lang="es">Devuelve la traza acumulada en memoria</p>
    METHODS ip_get_logs
      RETURNING VALUE(rt_logs) TYPE string_table.

    "! <p class="shorttext synchronized" lang="es">Fija el extracto en curso</p>
    "! Los mensajes posteriores se bufferizan para el BALI de ese UUID.
    METHODS ip_set_statement
      IMPORTING iv_uuid TYPE sysuuid_x16.

    "! <p class="shorttext synchronized" lang="es">Cierra el contexto de extracto</p>
    METHODS ip_clear_statement.

    "! <p class="shorttext synchronized" lang="es">Persiste los buffers en BALI</p>
    "! Escribe un log por extracto (external_id = UUID) y limpia el buffer.
    "! Best-effort: nunca interrumpe el proceso.
    METHODS ip_flush_to_bali.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_buffered,
             uuid     TYPE sysuuid_x16,
             severity TYPE c LENGTH 1,
             text     TYPE string,
           END OF ty_buffered.

    DATA tg_logs         TYPE string_table.
    DATA tg_buffered     TYPE STANDARD TABLE OF ty_buffered WITH EMPTY KEY.
    DATA wg_current_uuid TYPE sysuuid_x16.

    METHODS iv_add_log
      IMPORTING iv_level    TYPE string
                iv_severity TYPE zcl_bankstatement_applog=>ty_message-severity
                iv_message  TYPE string.

ENDCLASS.



CLASS ZCL_BANKSTATEMENT_LOGGER IMPLEMENTATION.


  METHOD ip_log_info.
    iv_add_log( iv_level = 'INFO' iv_severity = 'I' iv_message = iv_message ).
  ENDMETHOD.


  METHOD ip_log_warning.
    iv_add_log( iv_level = 'WARN' iv_severity = 'W' iv_message = iv_message ).
  ENDMETHOD.


  METHOD ip_log_error.
    iv_add_log( iv_level = 'ERROR' iv_severity = 'E' iv_message = iv_message ).
  ENDMETHOD.


  METHOD iv_add_log.
    DATA(wl_timestamp) = |{ cl_abap_context_info=>get_system_date( ) DATE = USER } { cl_abap_context_info=>get_system_time( ) TIME = USER }|.
    APPEND |{ wl_timestamp } [{ iv_level }] { iv_message }| TO tg_logs.

    " Si hay extracto en curso, bufferizar para su log BALI
    IF wg_current_uuid IS NOT INITIAL.
      APPEND VALUE #( uuid     = wg_current_uuid
                      severity = iv_severity
                      text     = iv_message ) TO tg_buffered.
    ENDIF.
  ENDMETHOD.


  METHOD ip_get_logs.
    rt_logs = tg_logs.
  ENDMETHOD.


  METHOD ip_set_statement.
    wg_current_uuid = iv_uuid.
  ENDMETHOD.


  METHOD ip_clear_statement.
    CLEAR wg_current_uuid.
  ENDMETHOD.


  METHOD ip_flush_to_bali.
    DATA tl_messages TYPE zcl_bankstatement_applog=>tt_message.
    DATA wl_uuid     TYPE sysuuid_x16.

    DATA(tl_buffer) = tg_buffered.
    CLEAR tg_buffered.

    IF tl_buffer IS INITIAL.
      RETURN.
    ENDIF.

    " Agrupar por UUID conservando el orden de inserción
    SORT tl_buffer STABLE BY uuid.

    LOOP AT tl_buffer INTO DATA(xl_row).
      IF wl_uuid IS NOT INITIAL AND xl_row-uuid <> wl_uuid.
        zcl_bankstatement_applog=>log_statement_messages( iv_statement_uuid = wl_uuid
                                                          it_messages       = tl_messages ).
        CLEAR tl_messages.
      ENDIF.
      wl_uuid = xl_row-uuid.
      APPEND VALUE #( severity = xl_row-severity
                      text     = xl_row-text ) TO tl_messages.
    ENDLOOP.

    IF tl_messages IS NOT INITIAL.
      zcl_bankstatement_applog=>log_statement_messages( iv_statement_uuid = wl_uuid
                                                        it_messages       = tl_messages ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
