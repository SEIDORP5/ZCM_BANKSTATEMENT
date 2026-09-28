*&---------------------------------------------------------------------*
*& Clase ZCL_BANKSTATEMENT_API_CLIENT - Cliente SOAP de contabilización
*&---------------------------------------------------------------------*
*& Comunica con la API estándar Bank Statement Posting (SAP_COM_0316).
*& Proxy: ZCO_BANK_STATEMENT_POST_IN.
*&---------------------------------------------------------------------*
CLASS zcl_bankstatement_api_client DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS constructor
      IMPORTING io_logger TYPE REF TO zcl_bankstatement_logger OPTIONAL.

    "! <p class="shorttext synchronized" lang="es">Envía los extractos a la API de contabilización</p>
    METHODS ip_post_statements
      IMPORTING
        it_parsed_data TYPE zcl_bankstatement_types=>tty_ebs_parse
        iv_job_mode    TYPE abap_boolean
      EXPORTING
        et_messages    TYPE zcl_bankstatement_types=>tty_soapmessageresponse
        ev_posted      TYPE i.

  PRIVATE SECTION.
    DATA go_logger TYPE REF TO zcl_bankstatement_logger.
    DATA go_proxy  TYPE REF TO zco_bank_statement_post_in.

    METHODS iv_setup_connection
      EXPORTING
        et_messages       TYPE zcl_bankstatement_types=>tty_soapmessageresponse
      RETURNING
        VALUE(rv_success) TYPE abap_boolean.

    METHODS iv_build_request
      IMPORTING
        is_ebs            TYPE zcl_bankstatement_types=>ty_ebs_parse
      RETURNING
        VALUE(rs_request) TYPE zbank_statement_request1.

    METHODS iv_update_statement_status
      IMPORTING
        iv_uuid     TYPE sysuuid_x16
        iv_status   TYPE zr_febh-status
        iv_message  TYPE string
        iv_job_mode TYPE abap_boolean
      EXPORTING
        et_messages TYPE zcl_bankstatement_types=>tty_soapmessageresponse.

ENDCLASS.



CLASS ZCL_BANKSTATEMENT_API_CLIENT IMPLEMENTATION.


  METHOD constructor.
    go_logger = COND #(
      WHEN io_logger IS BOUND
      THEN io_logger
      ELSE NEW zcl_bankstatement_logger( ) ).
  ENDMETHOD.


  METHOD ip_post_statements.

    TYPES: BEGIN OF ty_msg_for_handler,
             success TYPE i,
             nodata  TYPE i,
             error   TYPE i,
           END OF ty_msg_for_handler.

    DATA wl_posted          TYPE i VALUE 0.
    DATA tl_setup_messages  TYPE zcl_bankstatement_types=>tty_soapmessageresponse.
    DATA tl_update_messages TYPE zcl_bankstatement_types=>tty_soapmessageresponse.
    DATA xl_mg_for_handler  TYPE ty_msg_for_handler.

    CLEAR: et_messages, ev_posted.

    IF iv_setup_connection( IMPORTING et_messages = tl_setup_messages ) = abap_false.
      go_logger->ip_log_error( zcl_bankstatement_types=>msg( '020' ) ).
      et_messages = tl_setup_messages.
      RETURN.
    ENDIF.

    go_logger->ip_log_info( zcl_bankstatement_types=>msg( iv_number = '025'
                                                          iv_v1     = lines( it_parsed_data ) ) ).

    " Enviar en orden cronológico de periodo
    DATA(tl_sorted_data) = it_parsed_data.
    SORT tl_sorted_data BY periodstartdate ASCENDING.

    LOOP AT tl_sorted_data INTO DATA(xl_ebs).
      " Contexto BALI: los mensajes siguientes van al log de ESTE extracto
      go_logger->ip_set_statement( xl_ebs-sapuuid ).

      DATA(xl_request) = iv_build_request( xl_ebs ).

      IF xl_request-bank_statement_request-bank_statement_request_message-bank_statement_line_items IS INITIAL.

        go_logger->ip_log_warning( zcl_bankstatement_types=>msg( '012' ) ).

        iv_update_statement_status( EXPORTING iv_uuid     = xl_ebs-sapuuid
                                              iv_status   = zcl_bankstatement_types=>ebs_status-no_movements
                                              iv_message  = zcl_bankstatement_types=>msg( '012' )
                                              iv_job_mode = iv_job_mode
                                    IMPORTING et_messages = tl_update_messages ).

        APPEND LINES OF tl_update_messages TO et_messages.
        xl_mg_for_handler-nodata += 1.
        go_logger->ip_clear_statement( ).
        CONTINUE.
      ENDIF.

      TRY.
          go_proxy->bank_statement_post_in( EXPORTING input  = xl_request
                                            IMPORTING output = DATA(xl_response) ).

          DATA(wl_statement_id) = xl_response-bank_statement_response-bank_statement_response_messag-bank_statement_short_id.

          IF wl_statement_id IS NOT INITIAL AND wl_statement_id <> '00000000'.
            wl_posted += 1.

            DATA(wl_posted_msg) = zcl_bankstatement_types=>msg( iv_number = '013'
                                                                iv_v1     = wl_statement_id ).

            iv_update_statement_status( EXPORTING iv_uuid     = xl_ebs-sapuuid
                                                  iv_status   = zcl_bankstatement_types=>ebs_status-posted
                                                  iv_message  = wl_posted_msg
                                                  iv_job_mode = iv_job_mode
                                        IMPORTING et_messages = tl_update_messages ).

            APPEND LINES OF tl_update_messages TO et_messages.
            xl_mg_for_handler-success += 1.

            go_logger->ip_log_info( wl_posted_msg ).

          ELSE.
            " La API devolvió log de errores: concatenar las notas
            DATA(xl_log) = xl_response-bank_statement_response-log.
            DATA(tl_log_items) = xl_log-item.
            DATA(wl_error_msg) = zcl_bankstatement_types=>msg( '014' ).

            LOOP AT tl_log_items INTO DATA(xl_log_item).
              wl_error_msg = |{ wl_error_msg } { xl_log_item-note }|.
            ENDLOOP.

            wl_error_msg = condense( wl_error_msg ).

            iv_update_statement_status( EXPORTING iv_uuid     = xl_ebs-sapuuid
                                                  iv_status   = zcl_bankstatement_types=>ebs_status-error
                                                  iv_message  = wl_error_msg
                                                  iv_job_mode = iv_job_mode
                                        IMPORTING et_messages = tl_update_messages ).

            APPEND LINES OF tl_update_messages TO et_messages.
            xl_mg_for_handler-error += 1.
            go_logger->ip_log_error( wl_error_msg ).
          ENDIF.

        CATCH cx_soap_destination_error INTO DATA(lo_dest_error).
          DATA(wl_exception) = |{ zcl_bankstatement_types=>msg( '015' ) }: { lo_dest_error->get_longtext( ) }|.

          iv_update_statement_status( EXPORTING iv_uuid     = xl_ebs-sapuuid
                                                iv_status   = zcl_bankstatement_types=>ebs_status-error
                                                iv_message  = wl_exception
                                                iv_job_mode = iv_job_mode
                                      IMPORTING et_messages = tl_update_messages ).

          APPEND LINES OF tl_update_messages TO et_messages.

          APPEND VALUE #( messagetype        = 'E'
                          messagecontexttype = 1
                          message            = wl_exception )
                 TO et_messages.

          go_logger->ip_log_error( wl_exception ).

        CATCH cx_ai_system_fault INTO DATA(lo_sys_fault).
          wl_exception = |{ zcl_bankstatement_types=>msg( '016' ) }: { lo_sys_fault->get_longtext( ) }|.

          iv_update_statement_status( EXPORTING iv_uuid     = xl_ebs-sapuuid
                                                iv_status   = zcl_bankstatement_types=>ebs_status-error
                                                iv_message  = wl_exception
                                                iv_job_mode = iv_job_mode
                                      IMPORTING et_messages = tl_update_messages ).

          APPEND LINES OF tl_update_messages TO et_messages.

          APPEND VALUE #( messagetype        = 'E'
                          messagecontexttype = 1
                          message            = wl_exception )
                 TO et_messages.

          go_logger->ip_log_error( wl_exception ).
      ENDTRY.

      go_logger->ip_clear_statement( ).
      CLEAR: wl_statement_id, wl_error_msg, xl_request, xl_response, tl_update_messages.
    ENDLOOP.

    APPEND VALUE #(
        messagetype        = 'I'
        messagecontexttype = '2'
        message            = zcl_bankstatement_types=>msg( iv_number = '017'
                                                           iv_v1     = xl_mg_for_handler-success
                                                           iv_v2     = xl_mg_for_handler-error
                                                           iv_v3     = xl_mg_for_handler-nodata ) )
           TO et_messages.

    ev_posted = wl_posted.
  ENDMETHOD.


  METHOD iv_setup_connection.
    DATA wl_lr_cscn TYPE if_com_scenario_factory=>ty_query-cscn_id_range.

    rv_success = abap_false.
    CLEAR et_messages.

    TRY.
        " El destino SOAP se resuelve por el Communication Arrangement del
        " escenario de SALIDA; el sistema de comunicación se toma del propio
        " arrangement, no de un rango de nombres supuesto.
        wl_lr_cscn = VALUE #( ( sign = 'I' option = 'EQ'
                                low  = zcl_bankstatement_types=>c_sapbankstatementapi ) ).

        DATA(lo_factory) = cl_com_arrangement_factory=>create_instance( ).
        lo_factory->query_ca( EXPORTING is_query           = VALUE #( cscn_id_range = wl_lr_cscn )
                              IMPORTING et_com_arrangement = DATA(tl_ca) ).

        IF tl_ca IS INITIAL.
          DATA(wl_ca_error) = zcl_bankstatement_types=>msg( iv_number = '018'
                                                            iv_v1     = zcl_bankstatement_types=>c_sapbankstatementapi ).
          APPEND VALUE #( messagetype        = 'E'
                          messagecontexttype = 1
                          message            = wl_ca_error )
                 TO et_messages.
          go_logger->ip_log_error( wl_ca_error ).
          RETURN.
        ENDIF.

        DATA(wl_com_system) = tl_ca[ 1 ]->get_comm_system_id( ).

        DATA(lo_destination) = cl_soap_destination_provider=>create_by_comm_arrangement(
                                   comm_scenario  = zcl_bankstatement_types=>c_sapbankstatementapi
                                   comm_system_id = wl_com_system ).

        go_proxy = NEW zco_bank_statement_post_in( destination = lo_destination ).

        rv_success = abap_true.
        go_logger->ip_log_info( zcl_bankstatement_types=>msg( '019' ) ).

      CATCH cx_root INTO DATA(lo_error).
        DATA(wl_setup_error) = |{ zcl_bankstatement_types=>msg( '020' ) } | &&
                               |(escenario { zcl_bankstatement_types=>c_sapbankstatementapi }, | &&
                               |sistema { wl_com_system }): { lo_error->get_text( ) }|.
        APPEND VALUE #( messagetype        = 'E'
                        messagecontexttype = 1
                        message            = wl_setup_error )
               TO et_messages.
        go_logger->ip_log_error( wl_setup_error ).
    ENDTRY.
  ENDMETHOD.


  METHOD iv_build_request.
    rs_request-bank_statement_request-bank_statement_request_message-bank_statement_header = VALUE #(
      bank_number                                  = is_ebs-banknumber
      bank_country                                 = is_ebs-bankcountry
      swiftcode                                    = is_ebs-swift
      bank_account                                 = is_ebs-bankaccount
      bank_statement                               = is_ebs-bankstatement
      bank_statement_date                          = COND #( WHEN is_ebs-calculationdate IS NOT INITIAL
                                                             THEN is_ebs-calculationdate
                                                             ELSE is_ebs-periodenddate )
      bank_statement_period_start_da               = is_ebs-periodstartdate
      bank_statement_period_end_date               = is_ebs-periodenddate
      currency                                     = is_ebs-currency
      opening_bal_amt_in_bank_acct_c-content       = is_ebs-openingbalamtinbankacctc
      opening_bal_amt_in_bank_acct_c-currency_code = is_ebs-currency
      clsg_bal_amt_in_bk_acct_crcy-content         = is_ebs-clsgbalamtinbkacctcrcy
      clsg_bal_amt_in_bk_acct_crcy-currency_code   = is_ebs-currency
      total_debit_amt_in_bk_acct_crc-content       = is_ebs-totaldebitamtinbkacctcrc
      total_debit_amt_in_bk_acct_crc-currency_code = is_ebs-currency
      total_credit_amt_in_bk_acct_cr-content       = is_ebs-totalcreditamtinbkacctcr
      total_credit_amt_in_bk_acct_cr-currency_code = is_ebs-currency
      bank_statement_number_of_items               = is_ebs-bankstatementnumberofitems
      sender_iban                                  = is_ebs-iban ).

    " Agrupar posiciones por movimiento: la fila principal (sin nº de
    " concepto) crea el item; los registros 23 añaden líneas al concepto
    LOOP AT is_ebs-febep INTO DATA(xl_febp) GROUP BY ( iditem = xl_febp-iditem ) ASCENDING.

      APPEND INITIAL LINE TO rs_request-bank_statement_request-bank_statement_request_message-bank_statement_line_items
        ASSIGNING FIELD-SYMBOL(<fs_item>).

      LOOP AT GROUP xl_febp INTO DATA(xl_item_detail).

        IF xl_item_detail-iddescriptionitem IS INITIAL.
          <fs_item> = VALUE #(
            bank_posting_date                            = xl_item_detail-bankpostingdate
            value_date                                   = xl_item_detail-bankvaluedate
            amount_in_bank_account_currenc-content       = xl_item_detail-amountinbankaccountcurrency
            amount_in_bank_account_currenc-currency_code = is_ebs-currency
            payment_transaction_code                     = xl_item_detail-paymenttransactioncode
            bank_statement_item_descripti1               = xl_item_detail-bankstatementitemdescription1
            bank_statement_item_descriptio               = xl_item_detail-bankstatementitemdescription2
            business_partner                             = xl_item_detail-businesspartner
            check                                        = xl_item_detail-ebscheck ).

          IF xl_item_detail-notetopayeeinbankstatement IS NOT INITIAL.
            APPEND INITIAL LINE TO <fs_item>-note_to_payee_in_bank_statemen ASSIGNING FIELD-SYMBOL(<fs_note>).
            <fs_note> = xl_item_detail-notetopayeeinbankstatement.
          ENDIF.

        ELSEIF xl_item_detail-iddescriptionitem IS NOT INITIAL
           AND xl_item_detail-notetopayeeinbankstatement IS NOT INITIAL.
          APPEND INITIAL LINE TO <fs_item>-note_to_payee_in_bank_statemen ASSIGNING <fs_note>.

          DATA(wl_clean_note) = xl_item_detail-notetopayeeinbankstatement.
          REPLACE ALL OCCURRENCES OF PCRE '(\s)+' IN wl_clean_note WITH ` `.

          <fs_note> = wl_clean_note.
        ENDIF.

      ENDLOOP.

    ENDLOOP.

    rs_request-bank_statement_request-message_header-post_in_background = abap_true.
  ENDMETHOD.


  METHOD iv_update_statement_status.
    CLEAR et_messages.

    TRY.
        MODIFY ENTITIES OF zr_febh
               ENTITY febh
               UPDATE FIELDS ( status message )
               WITH VALUE #( ( sapuuid  = iv_uuid
                               status   = iv_status
                               message  = iv_message
                               %control = VALUE #( status  = if_abap_behv=>mk-on
                                                   message = if_abap_behv=>mk-on ) ) )
               FAILED DATA(xl_failed)
               REPORTED DATA(xl_reported).

        IF xl_failed IS NOT INITIAL.
          DATA(wl_update_error) = zcl_bankstatement_types=>msg( iv_number = '022'
                                                                iv_v1     = iv_uuid ).
          APPEND VALUE #( messagetype = 'E'
                          message     = wl_update_error )
                 TO et_messages.
          go_logger->ip_log_error( wl_update_error ).
        ENDIF.

        " COMMIT por extracto (deliberado): si el proceso muere a mitad,
        " los ya enviados quedan marcados y NO se reenvían al banco
        IF iv_job_mode = abap_true.
          COMMIT ENTITIES
                 RESPONSE OF zr_febh
                 FAILED DATA(xl_failed_commit)
                 REPORTED DATA(xl_reported_commit).

          IF sy-subrc <> 0 OR xl_failed_commit IS NOT INITIAL.
            DATA(wl_commit_error) = zcl_bankstatement_types=>msg( iv_number = '023'
                                                                  iv_v1     = iv_uuid ).
            APPEND VALUE #( messagetype = 'E'
                            message     = wl_commit_error )
                   TO et_messages.
            go_logger->ip_log_error( wl_commit_error ).
          ENDIF.
        ENDIF.

      CATCH cx_root INTO DATA(lo_error).
        DATA(wl_exc_error) = |{ zcl_bankstatement_types=>msg( iv_number = '022' iv_v1 = iv_uuid ) }: { lo_error->get_text( ) }|.
        APPEND VALUE #( messagetype = 'E'
                        message     = wl_exc_error )
               TO et_messages.
        go_logger->ip_log_error( wl_exc_error ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
