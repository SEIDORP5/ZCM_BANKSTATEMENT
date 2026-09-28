*&---------------------------------------------------------------------*
*& Clase ZCL_APJ_BANKSTATEMENT - Job APJ de proceso de extractos
*&---------------------------------------------------------------------*
*& Procesa desde el monitor los extractos que cumplan los filtros
*& (fichero, fecha, estado) y los envía a la API de contabilización.
*& Log de job en BALI (asignado al Application Job) + log por extracto
*& vía el logger del motor (external_id = UUID del extracto).
*&---------------------------------------------------------------------*
CLASS zcl_apj_bankstatement DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_apj_dt_exec_object.
    INTERFACES if_apj_rt_exec_object.
    INTERFACES if_oo_adt_classrun.

    METHODS constructor.

  PROTECTED SECTION.
  PRIVATE SECTION.
    METHODS iv_add_text_to_applog_console
      IMPORTING i_text TYPE cl_bali_free_text_setter=>ty_text
      RAISING   cx_bali_runtime.

    DATA out             TYPE REF TO if_oo_adt_classrun_out.
    DATA application_log TYPE REF TO if_bali_log.

ENDCLASS.



CLASS ZCL_APJ_BANKSTATEMENT IMPLEMENTATION.


  METHOD constructor.
    TRY.
        " Log de nivel job (se asigna al Application Job al guardar).
        " El log por extracto va aparte, con external_id = UUID del extracto.
        application_log = cl_bali_log=>create_with_header(
                              header = cl_bali_header_setter=>create( object      = 'ZAL_BANKSTATEMENT'
                                                                      subobject   = 'ZALS_BANKSTATEMENT'
                                                                      external_id = 'JOB' ) ).
      CATCH cx_bali_runtime.
        IF 1 = 2.
        ENDIF.
    ENDTRY.
  ENDMETHOD.


  METHOD if_apj_dt_exec_object~get_parameters.
    et_parameter_def = VALUE #(
        changeable_ind = abap_true
        ( selname = 'S_FILENA' kind = if_apj_dt_exec_object=>select_option datatype = 'C' length = 100
          param_text = 'Nombre de fichero' )
        ( selname = 'S_FILEDA' kind = if_apj_dt_exec_object=>select_option datatype = 'D'
          param_text = 'Fecha de fichero' )
        ( selname = 'S_STATUS' kind = if_apj_dt_exec_object=>select_option datatype = 'C' length = 1
          param_text = 'Estado (1=Inicial 2=Contab. 3=Error 4=Sin movim.)' ) ).

    " Por defecto se procesan los pendientes: inicial (1) y error (3)
    et_parameter_val = VALUE #(
        ( selname = 'S_STATUS' kind = if_apj_dt_exec_object=>select_option sign = 'I' option = 'EQ' low = '1' )
        ( selname = 'S_STATUS' kind = if_apj_dt_exec_object=>select_option sign = 'I' option = 'EQ' low = '3' ) ).
  ENDMETHOD.


  METHOD if_apj_rt_exec_object~execute.
    DATA rl_filename TYPE zcl_bankstatement_types=>tr_filename.
    DATA rl_filedate TYPE zcl_bankstatement_types=>tr_filedate.
    DATA rl_status   TYPE zcl_bankstatement_types=>tr_status.

    " Convertir los parámetros del job en rangos para el orquestador
    LOOP AT it_parameters INTO DATA(xl_parameter).
      DATA(wl_sign)   = COND #( WHEN xl_parameter-sign IS INITIAL THEN 'I' ELSE xl_parameter-sign ).
      DATA(wl_option) = COND #( WHEN xl_parameter-option IS NOT INITIAL THEN xl_parameter-option
                                WHEN xl_parameter-high IS NOT INITIAL THEN 'BT'
                                ELSE 'EQ' ).

      CASE xl_parameter-selname.
        WHEN 'S_FILENA'.
          APPEND VALUE #( sign = wl_sign option = wl_option
                          low = xl_parameter-low high = xl_parameter-high ) TO rl_filename.
        WHEN 'S_FILEDA'.
          APPEND VALUE #( sign = wl_sign option = wl_option
                          low = xl_parameter-low high = xl_parameter-high ) TO rl_filedate.
        WHEN 'S_STATUS'.
          APPEND VALUE #( sign = wl_sign option = wl_option
                          low = xl_parameter-low high = xl_parameter-high ) TO rl_status.
      ENDCASE.
      CLEAR xl_parameter.
    ENDLOOP.

    TRY.
        IF rl_filename IS NOT INITIAL.
          iv_add_text_to_applog_console( i_text = |Filtro fichero: { lines( rl_filename ) } condición(es)| ).
        ENDIF.
        IF rl_filedate IS NOT INITIAL.
          iv_add_text_to_applog_console( i_text = |Filtro fecha: { lines( rl_filedate ) } condición(es)| ).
        ENDIF.
        IF rl_status IS NOT INITIAL.
          iv_add_text_to_applog_console( i_text = |Filtro estado: { lines( rl_status ) } condición(es)| ).
        ENDIF.
      CATCH cx_bali_runtime.
        IF 1 = 2.
        ENDIF.
    ENDTRY.

    DATA(lo_orchestrator) = NEW zcl_bankstatement_orchestrator( ).

    " Los filtros se aplican de verdad en la selección del orquestador
    DATA(xl_result_db) = lo_orchestrator->ip_process_files_from_database(
                             ir_filename = rl_filename
                             ir_filedate = rl_filedate
                             ir_status   = rl_status
                             iv_job_mode = abap_true ).

    TRY.
        iv_add_text_to_applog_console( i_text = |{ zcl_bankstatement_types=>msg( iv_number = '027' iv_v1 = xl_result_db-total_files ) }| ).
        iv_add_text_to_applog_console( i_text = |{ zcl_bankstatement_types=>msg( iv_number = '028' iv_v1 = xl_result_db-statements_posted ) }| ).
        iv_add_text_to_applog_console( i_text = |Errores: { xl_result_db-errors }| ).
      CATCH cx_bali_runtime.
        IF 1 = 2.
        ENDIF.
    ENDTRY.

    LOOP AT xl_result_db-messages INTO DATA(xl_msg).
      TRY.
          iv_add_text_to_applog_console( i_text = |{ xl_msg-messagetype } { xl_msg-message }| ).
        CATCH cx_bali_runtime.
          IF 1 = 2.
          ENDIF.
      ENDTRY.
    ENDLOOP.

  ENDMETHOD.


  METHOD if_oo_adt_classrun~main.
    " Ejecución de prueba con los valores por defecto (pendientes 1 y 3)
    DATA et_parameters TYPE if_apj_rt_exec_object=>tt_templ_val.

    me->out = out.
    et_parameters = VALUE #(
      ( selname = 'S_STATUS' kind = if_apj_dt_exec_object=>select_option sign = 'I' option = 'EQ' low = '1' )
      ( selname = 'S_STATUS' kind = if_apj_dt_exec_object=>select_option sign = 'I' option = 'EQ' low = '3' ) ).

    TRY.
        if_apj_rt_exec_object~execute( it_parameters = et_parameters ).
        out->write( |Finalizado| ).
      CATCH cx_root INTO DATA(lx_error).
        out->write( |Se ha producido una excepción: { lx_error->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.


  METHOD iv_add_text_to_applog_console.
    IF sy-batch = abap_true.
      DATA(application_log_free_text) = cl_bali_free_text_setter=>create(
                                            severity = if_bali_constants=>c_severity_status
                                            text     = i_text ).
      application_log_free_text->set_detail_level( detail_level = '1' ).
      application_log->add_item( item = application_log_free_text ).
      cl_bali_log_db=>get_instance( )->save_log( log                        = application_log
                                                 assign_to_current_appl_job = abap_true ).
    ELSEIF out IS BOUND.
      out->write( i_text ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
