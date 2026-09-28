*&---------------------------------------------------------------------*
*& Clase ZCL_BANKSTATEMENT - Fachada del motor de extractos
*&---------------------------------------------------------------------*
*& Punto de entrada simplificado sobre el orquestador. El classrun (F9)
*& procesa los extractos PENDIENTES del monitor: contabiliza de verdad
*& contra la API estándar (no es una simulación).
*&---------------------------------------------------------------------*
CLASS zcl_bankstatement DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES tty_filestring          TYPE zcl_bankstatement_types=>tty_filestring.
    TYPES ty_import_file          TYPE zcl_bankstatement_types=>ty_import_file.
    TYPES tty_soapmessageresponse TYPE zcl_bankstatement_types=>tty_soapmessageresponse.
    TYPES tty_ebs_parse           TYPE zcl_bankstatement_types=>tty_ebs_parse.

    INTERFACES if_oo_adt_classrun.

    "! <p class="shorttext synchronized" lang="es">Decodifica y procesa ficheros entrantes</p>
    METHODS ip_decode_file
      IMPORTING imp_job             TYPE abap_boolean
                imt_file            TYPE zcl_bankstatement_types=>tty_import_file
                imp_format          TYPE string
      EXPORTING exp_countfiles      TYPE i
                exp_filesduplicated TYPE i.

    "! <p class="shorttext synchronized" lang="es">Procesa extractos del monitor</p>
    METHODS ip_process_files
      IMPORTING imp_job      TYPE abap_boolean
                it_keys      TYPE zcl_bankstatement_types=>tt_keys OPTIONAL
      EXPORTING exp_countebs TYPE i
                ext_messages TYPE tty_soapmessageresponse.

  PRIVATE SECTION.
    DATA go_orchestrator TYPE REF TO zcl_bankstatement_orchestrator.

ENDCLASS.



CLASS ZCL_BANKSTATEMENT IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.
    IF go_orchestrator IS NOT BOUND.
      go_orchestrator = NEW zcl_bankstatement_orchestrator( ).
    ENDIF.

    " job_mode = true: sin COMMIT los estados no se persistirían y los
    " extractos ya enviados se reenviarían en la siguiente ejecución
    DATA(xl_result) = go_orchestrator->ip_process_files_from_database( iv_job_mode = abap_true ).

    out->write( |Procesados: { xl_result-processed_files }| ).
    out->write( |Errores: { xl_result-errors }| ).
    out->write( |Enviados: { xl_result-statements_posted }| ).
  ENDMETHOD.


  METHOD ip_decode_file.
    IF go_orchestrator IS NOT BOUND.
      go_orchestrator = NEW zcl_bankstatement_orchestrator( ).
    ENDIF.

    DATA(xl_result) = go_orchestrator->ip_process_files_from_import( it_import_files = imt_file
                                                                     iv_format       = imp_format
                                                                     iv_job_mode     = imp_job ).

    exp_countfiles      = xl_result-processed_files.
    exp_filesduplicated = xl_result-duplicates.
  ENDMETHOD.


  METHOD ip_process_files.
    IF go_orchestrator IS NOT BOUND.
      go_orchestrator = NEW zcl_bankstatement_orchestrator( ).
    ENDIF.

    DATA(xl_result) = go_orchestrator->ip_process_files_from_database( it_keys     = it_keys
                                                                       iv_job_mode = imp_job ).

    exp_countebs = xl_result-statements_posted.
    ext_messages = xl_result-messages.
  ENDMETHOD.
ENDCLASS.
