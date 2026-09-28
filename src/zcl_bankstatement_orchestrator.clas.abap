*&---------------------------------------------------------------------*
*& Clase ZCL_BANKSTATEMENT_ORCHESTRATOR - Orquestador del proceso
*&---------------------------------------------------------------------*
*& Coordina el flujo completo: decodificación + análisis CSB43 +
*& control de duplicados + persistencia en el monitor (ZR_FEBH) +
*& envío al servicio de contabilización (SOAP SAP_COM_0316).
*&---------------------------------------------------------------------*
CLASS zcl_bankstatement_orchestrator DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_processing_result,
             total_files       TYPE i,
             processed_files   TYPE i,
             duplicates        TYPE i,
             errors            TYPE i,
             statements_posted TYPE i,
             messages          TYPE zcl_bankstatement_types=>tty_soapmessageresponse,
           END OF ty_processing_result.

    TYPES: BEGIN OF ty_decode_result,
             filename      TYPE string,
             success       TYPE abap_boolean,
             is_duplicate  TYPE abap_boolean,
             error_message TYPE string,
             ebs_data      TYPE zcl_bankstatement_types=>tty_ebs_parse,
           END OF ty_decode_result,
           tty_decode_result TYPE STANDARD TABLE OF ty_decode_result WITH DEFAULT KEY.

    TYPES tt_febh TYPE STANDARD TABLE OF zafebh.
    TYPES tt_febp TYPE STANDARD TABLE OF zafebp.

    METHODS constructor
      IMPORTING io_parser          TYPE REF TO zcl_bankstatement_parser_csb43 OPTIONAL
                io_duplicate_check TYPE REF TO zcl_bankstatement_dup_check    OPTIONAL
                io_logger          TYPE REF TO zcl_bankstatement_logger       OPTIONAL.

    "! <p class="shorttext synchronized" lang="es">Procesa ficheros entrantes (decodifica+analiza+envía)</p>
    METHODS ip_process_files_from_import
      IMPORTING it_import_files  TYPE zcl_bankstatement_types=>tty_import_file
                iv_format        TYPE string
                iv_job_mode      TYPE abap_boolean DEFAULT abap_false
      RETURNING VALUE(rs_result) TYPE ty_processing_result.

    "! <p class="shorttext synchronized" lang="es">Procesa extractos ya registrados en el monitor</p>
    "! Sin filtros procesa los pendientes (estado inicial o error). Con
    "! <em>it_keys</em> procesa esos UUID (si siguen pendientes: guard de
    "! idempotencia frente a envíos concurrentes).
    METHODS ip_process_files_from_database
      IMPORTING it_keys          TYPE zcl_bankstatement_types=>tt_keys     OPTIONAL
                ir_filename      TYPE zcl_bankstatement_types=>tr_filename OPTIONAL
                ir_filedate      TYPE zcl_bankstatement_types=>tr_filedate OPTIONAL
                ir_status        TYPE zcl_bankstatement_types=>tr_status   OPTIONAL
                iv_job_mode      TYPE abap_boolean                         DEFAULT abap_false
      RETURNING VALUE(rs_result) TYPE ty_processing_result.

  PRIVATE SECTION.
    DATA go_parser          TYPE REF TO zcl_bankstatement_parser_csb43.
    DATA go_duplicate_check TYPE REF TO zcl_bankstatement_dup_check.
    DATA go_logger          TYPE REF TO zcl_bankstatement_logger.
    DATA go_api_client      TYPE REF TO zcl_bankstatement_api_client.

    METHODS iv_decode_and_parse_files
      IMPORTING it_import_files TYPE zcl_bankstatement_types=>tty_import_file
                iv_format       TYPE string
      EXPORTING et_parsed_data  TYPE zcl_bankstatement_types=>tty_ebs_parse
                et_results      TYPE tty_decode_result
                ev_duplicates   TYPE i
                ev_errors       TYPE i.

    METHODS iv_persist_parsed_data
      IMPORTING it_parsed_data    TYPE zcl_bankstatement_types=>tty_ebs_parse
                iv_job_mode       TYPE abap_boolean
      RETURNING VALUE(rv_success) TYPE abap_boolean.

    METHODS iv_post_to_api
      IMPORTING it_parsed_data TYPE zcl_bankstatement_types=>tty_ebs_parse
                iv_job_mode    TYPE abap_boolean
      EXPORTING et_messages    TYPE zcl_bankstatement_types=>tty_soapmessageresponse
                ev_posted      TYPE i.

    METHODS iv_convert_db_to_parsed
      IMPORTING it_febh          TYPE tt_febh
                it_febp          TYPE tt_febp
      RETURNING VALUE(rt_parsed) TYPE zcl_bankstatement_types=>tty_ebs_parse.

ENDCLASS.



CLASS ZCL_BANKSTATEMENT_ORCHESTRATOR IMPLEMENTATION.


  METHOD constructor.
    " Dependencias inyectables (tests); por defecto se instancian aquí
    go_parser = COND #(
      WHEN io_parser IS BOUND THEN io_parser
      ELSE NEW zcl_bankstatement_parser_csb43( ) ).

    go_duplicate_check = COND #(
      WHEN io_duplicate_check IS BOUND THEN io_duplicate_check
      ELSE NEW zcl_bankstatement_dup_check( ) ).

    go_logger = COND #(
      WHEN io_logger IS BOUND THEN io_logger
      ELSE NEW zcl_bankstatement_logger( ) ).

    go_api_client = NEW zcl_bankstatement_api_client( io_logger = go_logger ).
  ENDMETHOD.


  METHOD ip_process_files_from_import.
    DATA tl_parsed_data    TYPE zcl_bankstatement_types=>tty_ebs_parse.
    DATA tl_decode_results TYPE tty_decode_result.

    CLEAR rs_result.
    rs_result-total_files = lines( it_import_files ).

    go_logger->ip_log_info( zcl_bankstatement_types=>msg( iv_number = '001'
                                                          iv_v1     = rs_result-total_files ) ).

    iv_decode_and_parse_files( EXPORTING it_import_files = it_import_files
                                         iv_format       = iv_format
                               IMPORTING et_parsed_data  = tl_parsed_data
                                         et_results      = tl_decode_results
                                         ev_duplicates   = rs_result-duplicates
                                         ev_errors       = rs_result-errors ).

    " Los errores por fichero se devuelven al llamador (contexto 2)
    LOOP AT tl_decode_results INTO DATA(xl_decode_result) WHERE success = abap_false.
      IF xl_decode_result-is_duplicate = abap_false.
        DATA(wl_file_error) = zcl_bankstatement_types=>msg( iv_number = '002'
                                                            iv_v1     = xl_decode_result-filename
                                                            iv_v2     = xl_decode_result-error_message ).
        go_logger->ip_log_error( wl_file_error ).

        APPEND VALUE #( messagetype        = 'E'
                        messagecontexttype = 2
                        message            = wl_file_error )
               TO rs_result-messages.
      ENDIF.
    ENDLOOP.

    IF tl_parsed_data IS INITIAL.
      go_logger->ip_log_info( zcl_bankstatement_types=>msg( '008' ) ).
      go_logger->ip_flush_to_bali( ).
      RETURN.
    ENDIF.

    go_logger->ip_log_info( zcl_bankstatement_types=>msg( iv_number = '007'
                                                          iv_v1     = lines( tl_parsed_data ) ) ).

    DATA(wl_persist_success) = iv_persist_parsed_data( it_parsed_data = tl_parsed_data
                                                       iv_job_mode    = iv_job_mode ).

    IF wl_persist_success = abap_false.
      go_logger->ip_log_error( zcl_bankstatement_types=>msg( '009' ) ).
      rs_result-errors += lines( tl_parsed_data ).

      APPEND VALUE #( messagetype        = 'E'
                      messagecontexttype = 3
                      message            = zcl_bankstatement_types=>msg( '009' ) )
             TO rs_result-messages.

      go_logger->ip_flush_to_bali( ).
      RETURN.
    ELSE.
      APPEND VALUE #( messagetype        = 'S'
                      messagecontexttype = 3
                      message            = zcl_bankstatement_types=>msg( '010' ) )
             TO rs_result-messages.
    ENDIF.

    rs_result-processed_files = lines( tl_parsed_data ).
    go_logger->ip_log_info( zcl_bankstatement_types=>msg( iv_number = '011'
                                                          iv_v1     = rs_result-processed_files ) ).

    iv_post_to_api( EXPORTING it_parsed_data = tl_parsed_data
                              iv_job_mode    = iv_job_mode
                    IMPORTING et_messages    = DATA(tl_posting_messages)
                              ev_posted      = rs_result-statements_posted ).

    go_logger->ip_log_info( zcl_bankstatement_types=>msg( iv_number = '028'
                                                          iv_v1     = rs_result-statements_posted ) ).

    LOOP AT tl_posting_messages INTO DATA(xl_posting_msg).
      APPEND xl_posting_msg TO rs_result-messages.
    ENDLOOP.

    " Persistir la traza por extracto en BALI (best-effort)
    go_logger->ip_flush_to_bali( ).
  ENDMETHOD.


  METHOD ip_process_files_from_database.
    DATA tl_febh        TYPE tt_febh.
    DATA tl_febp        TYPE tt_febp.
    DATA tl_parsed_data TYPE zcl_bankstatement_types=>tty_ebs_parse.

    CLEAR rs_result.

    " Rango de UUIDs solicitados (vacío = sin restricción)
    DATA(rl_uuid) = VALUE zcl_bankstatement_types=>tr_sapuuid(
                        FOR xl_key IN it_keys
                        ( sign = 'I' option = 'EQ' low = xl_key-sapuuid ) ).

    " Guard de idempotencia: solo estados pendientes salvo filtro explícito
    DATA(rl_status) = COND zcl_bankstatement_types=>tr_status(
        WHEN ir_status IS NOT INITIAL
        THEN ir_status
        ELSE VALUE #( ( sign = 'I' option = 'EQ' low = zcl_bankstatement_types=>ebs_status-initial )
                      ( sign = 'I' option = 'EQ' low = zcl_bankstatement_types=>ebs_status-error ) ) ).

    IF it_keys IS INITIAL.
      go_logger->ip_log_info( zcl_bankstatement_types=>msg( '024' ) ).
    ELSE.
      go_logger->ip_log_info( zcl_bankstatement_types=>msg( iv_number = '025'
                                                            iv_v1     = lines( it_keys ) ) ).
    ENDIF.

    " Lista de campos explícita: los LOB (fileheaddata/bgpf_monitor) no se
    " necesitan para el envío y penalizan la lectura
    SELECT sapuuid, externalid, bankstatement, filename, bankcountry,
           banknumber, bankaccount, iban, swift, ebsformat,
           periodstartdate, periodenddate, currency,
           openingbalamtinbankacctc, clsgbalamtinbkacctcrcy,
           totaldebitamtinbkacctcrc, totalcreditamtinbkacctcr,
           bankstatementnumberofitems, filecreationdate,
           calculatedpostingdate, status
      FROM zafebh
      WITH PRIVILEGED ACCESS
      WHERE sapuuid          IN @rl_uuid
        AND filename         IN @ir_filename
        AND filecreationdate IN @ir_filedate
        AND status           IN @rl_status
      INTO CORRESPONDING FIELDS OF TABLE @tl_febh.

    IF tl_febh IS INITIAL.
      go_logger->ip_log_info( zcl_bankstatement_types=>msg( '026' ) ).
      go_logger->ip_flush_to_bali( ).
      RETURN.
    ENDIF.

    DATA(rl_parent) = VALUE zcl_bankstatement_types=>tr_sapuuid(
                          FOR xl_hdr IN tl_febh
                          ( sign = 'I' option = 'EQ' low = xl_hdr-sapuuid ) ).

    SELECT sap_uuid, sap_parent_uuid, bankpostingdate, bankvaluedate,
           amountinbankaccountcurrency, feeamountintransactioncrcy,
           paymenttransactioncode, debitcreditcode, ebscheck,
           businesspartner, bankstatementitemdescription1,
           bankstatementitemdescription2, notetopayeeinbankstatement,
           iditem, iddescriptionitem
      FROM zafebp
      WITH PRIVILEGED ACCESS
      WHERE sap_parent_uuid IN @rl_parent
      INTO CORRESPONDING FIELDS OF TABLE @tl_febp.

    rs_result-total_files = lines( tl_febh ).
    go_logger->ip_log_info( zcl_bankstatement_types=>msg( iv_number = '027'
                                                          iv_v1     = rs_result-total_files ) ).

    tl_parsed_data = iv_convert_db_to_parsed( it_febh = tl_febh
                                              it_febp = tl_febp ).

    iv_post_to_api( EXPORTING it_parsed_data = tl_parsed_data
                              iv_job_mode    = iv_job_mode
                    IMPORTING et_messages    = rs_result-messages
                              ev_posted      = rs_result-statements_posted ).

    rs_result-processed_files = rs_result-statements_posted.
    go_logger->ip_log_info( zcl_bankstatement_types=>msg( iv_number = '028'
                                                          iv_v1     = rs_result-statements_posted ) ).

    " Persistir la traza por extracto en BALI (best-effort)
    go_logger->ip_flush_to_bali( ).
  ENDMETHOD.


  METHOD iv_decode_and_parse_files.
    DATA tl_string_content TYPE zcl_bankstatement_types=>tty_filestring.
    DATA xl_result         TYPE ty_decode_result.
    DATA xl_dup_check      TYPE zcl_bankstatement_dup_check=>ty_duplicate_check_result.

    CLEAR: et_parsed_data, et_results, ev_duplicates, ev_errors.

    DATA(tl_dup_results) = go_duplicate_check->ip_check_batch_exists( it_import_files ).

    LOOP AT it_import_files INTO DATA(xl_import_file).
      DATA(wl_index) = sy-tabix.

      CLEAR xl_result.
      xl_result-filename = xl_import_file-filename.
      xl_result-success  = abap_false.

      " El resultado del control de duplicados va en paralelo por índice;
      " limpiar antes de leer para no arrastrar la fila anterior
      CLEAR xl_dup_check.
      READ TABLE tl_dup_results INDEX wl_index INTO xl_dup_check.

      IF sy-subrc = 0 AND xl_dup_check-is_duplicate = abap_true.
        ev_duplicates += 1.
        xl_result-is_duplicate  = abap_true.
        xl_result-error_message = xl_dup_check-message.
        go_logger->ip_log_warning( xl_dup_check-message ).
        APPEND xl_result TO et_results.
        CONTINUE.
      ENDIF.

      TRY.
          DATA(wl_decoded) = zcl_decoding_bankstatement=>base64_to_utf8(
            i_content_base64 = xl_import_file-content ).

          " Separar en líneas según el tipo de salto presente
          CLEAR tl_string_content.
          IF wl_decoded CS cl_abap_char_utilities=>cr_lf.
            SPLIT wl_decoded AT cl_abap_char_utilities=>cr_lf
                  INTO TABLE tl_string_content.
          ELSEIF wl_decoded CS cl_abap_char_utilities=>newline.
            SPLIT wl_decoded AT cl_abap_char_utilities=>newline
                  INTO TABLE tl_string_content.
          ELSE.
            xl_result-error_message = zcl_bankstatement_types=>msg( '003' ).
            go_logger->ip_log_error( |{ xl_result-error_message } - { xl_import_file-filename }| ).
            ev_errors += 1.
            APPEND xl_result TO et_results.
            CONTINUE.
          ENDIF.

          DELETE tl_string_content WHERE table_line IS INITIAL.

          IF tl_string_content IS INITIAL.
            xl_result-error_message = zcl_bankstatement_types=>msg( '004' ).
            go_logger->ip_log_error( |{ xl_result-error_message } - { xl_import_file-filename }| ).
            ev_errors += 1.
            APPEND xl_result TO et_results.
            CONTINUE.
          ENDIF.

          DATA(xl_parse_result) = go_parser->ip_parse(
            iv_filename = xl_import_file-filename
            iv_filedate = xl_import_file-filedate
            it_content  = tl_string_content ).

          IF xl_parse_result-success = abap_true.
            xl_result-success  = abap_true.
            xl_result-ebs_data = xl_parse_result-ebs_data.
            APPEND LINES OF xl_parse_result-ebs_data TO et_parsed_data.
            go_logger->ip_log_info( zcl_bankstatement_types=>msg( iv_number = '005'
                                                                  iv_v1     = xl_import_file-filename ) ).
          ELSE.
            xl_result-error_message = xl_parse_result-message.
            go_logger->ip_log_error( xl_parse_result-message ).
            ev_errors += 1.
          ENDIF.

        CATCH cx_root INTO DATA(lo_error).
          xl_result-error_message = |{ zcl_bankstatement_types=>msg( '029' ) }: { lo_error->get_text( ) }|.
          go_logger->ip_log_error( |{ xl_result-error_message } - { xl_import_file-filename }| ).
          ev_errors += 1.
      ENDTRY.

      APPEND xl_result TO et_results.
    ENDLOOP.

  ENDMETHOD.


  METHOD iv_persist_parsed_data.
    DATA tl_create_febh TYPE TABLE FOR CREATE zr_febh.
    DATA tl_create_febp TYPE TABLE FOR CREATE zr_febh\_febp.

    rv_success = abap_false.

    TRY.
        tl_create_febh = VALUE #( FOR xl_ebs IN it_parsed_data
                                  ( CORRESPONDING #( xl_ebs MAPPING %cid = externalid ) ) ).

        tl_create_febp = VALUE #( FOR xl_ebs IN it_parsed_data
                                  ( %cid_ref = xl_ebs-externalid
                                    %target  = CORRESPONDING #( xl_ebs-febep ) ) ).

        MODIFY ENTITIES OF zr_febh
               ENTITY febh
               CREATE FIELDS ( sapuuid bankaccount bankcountry externalid bankstatement
                              filename banknumber iban swift fileheaddata ebsformat
                              periodstartdate periodenddate currency
                              openingbalamtinbankacctc clsgbalamtinbkacctcrcy
                              totaldebitamtinbkacctcrc totalcreditamtinbkacctcr
                              bankstatementnumberofitems filecreationdate
                              calculationdate status )
               WITH tl_create_febh
               CREATE BY \_febp AUTO FILL CID
               FIELDS ( bankpostingdate bankvaluedate amountinbankaccountcurrency
                       paymenttransactioncode debitcreditcode businesspartner
                       bankstatementitemdescription1 bankstatementitemdescription2
                       notetopayeeinbankstatement iditem iddescriptionitem fileitemdata )
               WITH tl_create_febp
               MAPPED DATA(xl_mapped)
               FAILED DATA(xl_failed)
               REPORTED DATA(xl_reported).

        IF xl_failed IS INITIAL.
          rv_success = abap_true.
          go_logger->ip_log_info( zcl_bankstatement_types=>msg( iv_number = '011'
                                                                iv_v1     = lines( it_parsed_data ) ) ).

          IF iv_job_mode = abap_true.
            COMMIT ENTITIES
                   RESPONSE OF zr_febh
                   FAILED DATA(xl_failed_commit)
                   REPORTED DATA(xl_reported_commit).

            IF sy-subrc <> 0 OR xl_failed_commit IS NOT INITIAL.
              rv_success = abap_false.
              go_logger->ip_log_error( zcl_bankstatement_types=>msg( '033' ) ).
            ENDIF.
          ENDIF.

        ELSE.
          go_logger->ip_log_error( zcl_bankstatement_types=>msg( '009' ) ).
        ENDIF.

      CATCH cx_root INTO DATA(lo_error).
        go_logger->ip_log_error( |{ zcl_bankstatement_types=>msg( '009' ) }: { lo_error->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.


  METHOD iv_post_to_api.
    go_api_client->ip_post_statements( EXPORTING it_parsed_data = it_parsed_data
                                                 iv_job_mode    = iv_job_mode
                                       IMPORTING et_messages    = et_messages
                                                 ev_posted      = ev_posted ).

  ENDMETHOD.


  METHOD iv_convert_db_to_parsed.
    DATA xl_parsed TYPE zcl_bankstatement_types=>ty_ebs_parse.
    DATA tl_febep  TYPE zcl_bankstatement_types=>tty_febep.
    DATA xl_febep  TYPE zcl_bankstatement_types=>ty_febep.

    CLEAR rt_parsed.

    LOOP AT it_febh INTO DATA(xl_febh).

      CLEAR xl_parsed.
      xl_parsed = CORRESPONDING #( xl_febh ).
      " La fecha de cálculo tiene nombre distinto en tabla y CDS
      xl_parsed-febh = CORRESPONDING zr_febh( xl_febh MAPPING calculationdate = calculatedpostingdate ).

      CLEAR tl_febep.
      LOOP AT it_febp INTO DATA(xl_febp_src)
           WHERE sap_parent_uuid = xl_febh-sapuuid.
        xl_febep = CORRESPONDING #( xl_febp_src ).
        APPEND xl_febep TO tl_febep.
      ENDLOOP.

      xl_parsed-febep = tl_febep.
      APPEND xl_parsed TO rt_parsed.

    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
