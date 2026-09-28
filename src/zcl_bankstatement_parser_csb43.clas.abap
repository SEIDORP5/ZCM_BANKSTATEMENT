*&---------------------------------------------------------------------*
*& Clase ZCL_BANKSTATEMENT_PARSER_CSB43 - Analizador del formato CSB43
*&---------------------------------------------------------------------*
*& Convierte el contenido de un fichero norma 43 (AEB) en la estructura
*& de extractos del monitor (cabecera + posiciones + conceptos).
*& Nota: el registro 33 (totales) NO se valida actualmente; pendiente de
*& decisión funcional (la acumulación de totales usa signo empresa).
*&---------------------------------------------------------------------*
CLASS zcl_bankstatement_parser_csb43 DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_parse_result,
             success  TYPE abap_boolean,
             message  TYPE string,
             ebs_data TYPE zcl_bankstatement_types=>tty_ebs_parse,
           END OF ty_parse_result.

    METHODS constructor
      IMPORTING it_currency    TYPE zcl_bankstatement_types=>tt_currency                OPTIONAL
                it_bankaccount TYPE zcl_bankstatement_types=>tt_housebankaccountlinkage OPTIONAL.

    "! <p class="shorttext synchronized" lang="es">Analiza el contenido de un fichero CSB43</p>
    METHODS ip_parse
      IMPORTING iv_filename      TYPE zr_febh-filename
                iv_filedate      TYPE datum
                it_content       TYPE zcl_bankstatement_types=>tty_filestring
      RETURNING VALUE(rs_result) TYPE ty_parse_result.

    TYPES ty_febep TYPE zr_febp.

  PRIVATE SECTION.
    DATA tg_currency    TYPE TABLE OF i_currency.
    DATA tg_bankaccount TYPE TABLE OF i_housebankaccountlinkage.
    DATA tg_ebs_parse   TYPE zcl_bankstatement_types=>tty_ebs_parse.

    METHODS iv_process_header_record
      IMPORTING iv_content    TYPE string
                iv_filename   TYPE zr_febh-filename
                iv_filedate   TYPE datum
                iv_headcount  TYPE i
      RETURNING VALUE(rs_ebs) TYPE zcl_bankstatement_types=>ty_ebs_parse.

    METHODS iv_process_item_record
      IMPORTING iv_content     TYPE string
                iv_itemcount   TYPE zr_febp-iditem
      RETURNING VALUE(rs_item) TYPE zr_febp.

    METHODS iv_process_detail_record
      IMPORTING iv_content      TYPE string
                iv_itemcount    TYPE zr_febp-iditem
                iv_descrcount   TYPE zr_febp-iddescriptionitem
      RETURNING VALUE(rt_items) TYPE zcl_bankstatement_types=>tty_febep.

    METHODS iv_process_footer_record
      IMPORTING iv_content      TYPE string
                is_ebs          TYPE zcl_bankstatement_types=>ty_ebs_parse
      RETURNING VALUE(rv_valid) TYPE abap_boolean.

    METHODS iv_extract_field
      IMPORTING iv_content      TYPE string
                iv_offset       TYPE i
                iv_length       TYPE i
      RETURNING VALUE(rv_field) TYPE string.

    METHODS iv_convert_amount
      IMPORTING iv_amount_str    TYPE string
                iv_debit_credit  TYPE c
      RETURNING VALUE(rv_amount) TYPE zr_febp-AmountInBankAccountCurrency.

    METHODS iv_generate_uuid
      RETURNING VALUE(rv_uuid) TYPE sysuuid_x16.

ENDCLASS.



CLASS ZCL_BANKSTATEMENT_PARSER_CSB43 IMPLEMENTATION.


  METHOD constructor.
    IF it_currency IS SUPPLIED.
      tg_currency = it_currency.
    ELSE.
      SELECT *
        FROM i_currency
        WITH PRIVILEGED ACCESS
        INTO TABLE @tg_currency. "#EC CI_NOWHERE
    ENDIF.

    IF it_bankaccount IS SUPPLIED.
      tg_bankaccount = it_bankaccount.
    ELSE.
      SELECT *
        FROM i_housebankaccountlinkage
        WITH PRIVILEGED ACCESS
        INTO TABLE @tg_bankaccount. "#EC CI_NOWHERE
    ENDIF.
  ENDMETHOD.


  METHOD ip_parse.
    DATA wl_headcount      TYPE i                         VALUE 0.
    DATA wl_itemcount      TYPE zr_febp-iditem            VALUE 0.
    DATA wl_itemdescrcount TYPE zr_febp-iddescriptionitem VALUE 0.
    DATA xl_current_ebs    TYPE zcl_bankstatement_types=>ty_ebs_parse.
    DATA xl_current_item   TYPE zr_febp.
    DATA tl_detail_items   TYPE zcl_bankstatement_types=>tty_febep.

    CLEAR tg_ebs_parse.
    rs_result-success = abap_true.

    TRY.
        LOOP AT it_content INTO DATA(wl_line).
          DATA(wl_record_type) = wl_line(2).

          CASE wl_record_type.
            WHEN zcl_csb43_constants=>c_record_type_header.
              " Un fichero puede traer varios extractos: cerrar el anterior
              IF wl_headcount > 0 AND xl_current_ebs IS NOT INITIAL.
                APPEND xl_current_ebs TO tg_ebs_parse.
              ENDIF.

              wl_headcount += 1.
              wl_itemcount = 0.

              xl_current_ebs = iv_process_header_record( iv_content   = wl_line
                                                         iv_filename  = iv_filename
                                                         iv_filedate  = iv_filedate
                                                         iv_headcount = wl_headcount ).

            WHEN zcl_csb43_constants=>c_record_type_item.
              wl_itemcount += 1.
              wl_itemdescrcount = 0.

              xl_current_item = iv_process_item_record( iv_content   = wl_line
                                                        iv_itemcount = wl_itemcount ).

              xl_current_ebs-bankstatementnumberofitems += 1.
              xl_current_ebs-clsgbalamtinbkacctcrcy     += xl_current_item-AmountInBankAccountCurrency.

              IF xl_current_item-DebitCreditCode = zcl_csb43_constants=>c_debit_code.
                xl_current_ebs-totaldebitamtinbkacctcrc += xl_current_item-AmountInBankAccountCurrency.
              ELSE.
                xl_current_ebs-totalcreditamtinbkacctcr += xl_current_item-AmountInBankAccountCurrency.
              ENDIF.

              APPEND xl_current_item TO xl_current_ebs-febep.

            WHEN zcl_csb43_constants=>c_record_type_detail.
              " Conceptos complementarios (hasta 5 registros 23 por movimiento)
              wl_itemdescrcount += 1.

              tl_detail_items = iv_process_detail_record( iv_content    = wl_line
                                                          iv_itemcount  = wl_itemcount
                                                          iv_descrcount = wl_itemdescrcount ).

              APPEND LINES OF tl_detail_items TO xl_current_ebs-febep.

            WHEN zcl_csb43_constants=>c_record_type_footer.
              " Registro 33: totales de control. Sin validar (ver cabecera).
          ENDCASE.
        ENDLOOP.

        IF xl_current_ebs IS NOT INITIAL.
          APPEND xl_current_ebs TO tg_ebs_parse.
        ENDIF.

        rs_result-ebs_data = tg_ebs_parse.

      CATCH cx_root INTO DATA(lx_error).
        rs_result-success = abap_false.
        rs_result-message = |{ zcl_bankstatement_types=>msg( '030' ) }: { lx_error->get_text( ) }|.
    ENDTRY.
  ENDMETHOD.


  METHOD iv_process_header_record.
    DATA wl_debit_credit TYPE c LENGTH 1.

    DATA(wl_bank_code) = iv_extract_field( iv_content = iv_content
                                           iv_offset  = zcl_csb43_constants=>c_h_bank_code_offset
                                           iv_length  = zcl_csb43_constants=>c_h_bank_code_length ).

    DATA(wl_account) = iv_extract_field( iv_content = iv_content
                                         iv_offset  = zcl_csb43_constants=>c_h_account_offset
                                         iv_length  = zcl_csb43_constants=>c_h_account_length ).

    DATA(wl_currency_key) = iv_extract_field( iv_content = iv_content
                                              iv_offset  = zcl_csb43_constants=>c_h_currency_offset
                                              iv_length  = zcl_csb43_constants=>c_h_currency_length ).

    READ TABLE tg_currency
         WITH KEY AlternativeCurrencyKey = wl_currency_key
         INTO DATA(xl_currency).

    READ TABLE tg_bankaccount
         WITH KEY BankNumber  = wl_bank_code
                  BankAccount = wl_account
         INTO DATA(xl_bankacc).

    rs_ebs = VALUE #( sapuuid          = iv_generate_uuid( )
                      externalid       = |{ iv_filename }-{ iv_headcount }|
                      filename         = iv_filename
                      filecreationdate = iv_filedate
                      ebsformat        = 'CSB43'
                      fileheaddata     = iv_content
                      banknumber       = wl_bank_code
                      bankaccount      = wl_account
                      swift            = xl_bankacc-SWIFTCode
                      iban             = xl_bankacc-Iban
                      bankcountry      = xl_bankacc-BankCountry
                      currency         = xl_currency-currency
                      status           = zcl_bankstatement_types=>ebs_status-initial ).

    DATA(wl_start_date) = iv_extract_field( iv_content = iv_content
                                            iv_offset  = zcl_csb43_constants=>c_h_start_date_offset
                                            iv_length  = zcl_csb43_constants=>c_h_start_date_length ).
    rs_ebs-periodstartdate = |20{ wl_start_date }|.

    DATA(wl_end_date) = iv_extract_field( iv_content = iv_content
                                          iv_offset  = zcl_csb43_constants=>c_h_end_date_offset
                                          iv_length  = zcl_csb43_constants=>c_h_end_date_length ).
    rs_ebs-periodenddate = |20{ wl_end_date }|.

    " Nº de extracto derivado de la fecha fin (MMDD sin cero inicial)
    rs_ebs-bankstatement = rs_ebs-periodenddate+4(4).
    IF rs_ebs-bankstatement(1) = '0'.
      rs_ebs-bankstatement = rs_ebs-bankstatement+1.
    ENDIF.

    wl_debit_credit = iv_extract_field( iv_content = iv_content
                                        iv_offset  = zcl_csb43_constants=>c_h_debit_credit_offset
                                        iv_length  = 1 ).

    DATA(wl_amount) = iv_extract_field( iv_content = iv_content
                                        iv_offset  = zcl_csb43_constants=>c_h_amount_offset
                                        iv_length  = zcl_csb43_constants=>c_h_amount_length ).

    rs_ebs-openingbalamtinbankacctc = iv_convert_amount( iv_amount_str   = wl_amount
                                                         iv_debit_credit = wl_debit_credit ).

    rs_ebs-clsgbalamtinbkacctcrcy   = rs_ebs-openingbalamtinbankacctc.
  ENDMETHOD.


  METHOD iv_process_item_record.
    DATA wl_debit_credit TYPE c LENGTH 1.

    DATA(wl_posting_date) = iv_extract_field( iv_content = iv_content
                                              iv_offset  = zcl_csb43_constants=>c_i_posting_date_offset
                                              iv_length  = zcl_csb43_constants=>c_i_posting_date_length ).

    DATA(wl_value_date) = iv_extract_field( iv_content = iv_content
                                            iv_offset  = zcl_csb43_constants=>c_i_value_date_offset
                                            iv_length  = zcl_csb43_constants=>c_i_value_date_length ).

    DATA(wl_trans_code) = iv_extract_field( iv_content = iv_content
                                            iv_offset  = zcl_csb43_constants=>c_i_trans_code_offset
                                            iv_length  = zcl_csb43_constants=>c_i_trans_code_length ).

    DATA(wl_trans_subcode) = iv_extract_field( iv_content = iv_content
                                               iv_offset  = zcl_csb43_constants=>c_i_trans_subcode_offset
                                               iv_length  = zcl_csb43_constants=>c_i_trans_subcode_length ).

    wl_debit_credit = iv_extract_field( iv_content = iv_content
                                        iv_offset  = zcl_csb43_constants=>c_i_debit_credit_offset
                                        iv_length  = 1 ).

    DATA(wl_amount) = iv_extract_field( iv_content = iv_content
                                        iv_offset  = zcl_csb43_constants=>c_i_amount_offset
                                        iv_length  = zcl_csb43_constants=>c_i_amount_length ).

    " Ojo: la clave debe/haber del banco se INVIERTE a óptica empresa:
    " debe del banco (1, salida de dinero) = haber contable 'H' y viceversa.
    " Es correcto contablemente: NO "arreglarlo".
    rs_item = VALUE #( sapuuid                     = iv_generate_uuid( )
                       iditem                      = iv_itemcount
                       bankpostingdate             = |20{ wl_posting_date }|
                       bankvaluedate               = |20{ wl_value_date }|
                       paymenttransactioncode      = |{ wl_trans_code } { wl_trans_subcode }|
                       debitcreditcode             = COND #(
                         WHEN wl_debit_credit = zcl_csb43_constants=>c_debit_indicator
                         THEN zcl_csb43_constants=>c_credit_code
                         ELSE zcl_csb43_constants=>c_debit_code )
                       amountinbankaccountcurrency = iv_convert_amount( iv_amount_str   = wl_amount
                                                                        iv_debit_credit = wl_debit_credit )
                       fileitemdata                = iv_content ).
  ENDMETHOD.


  METHOD iv_process_detail_record.
    DATA(wl_description) = iv_content+zcl_csb43_constants=>c_d_description_offset.
    REPLACE ALL OCCURRENCES OF PCRE '(\s)+' IN wl_description WITH ` `.

    " Cada registro 23 conserva su secuencia (iddescriptionitem) dentro del movimiento
    APPEND VALUE #( sapuuid                    = iv_generate_uuid( )
                    iditem                     = iv_itemcount
                    iddescriptionitem          = iv_descrcount
                    notetopayeeinbankstatement = wl_description
                    fileitemdata               = iv_content )
           TO rt_items.
  ENDMETHOD.


  METHOD iv_process_footer_record.
    DATA wl_closing_indicator TYPE c LENGTH 1.
    CONSTANTS c_tolerance TYPE p LENGTH 15 DECIMALS 6 VALUE '0.01'.

    DATA(wl_credit_amount) = iv_convert_amount( iv_amount_str   = iv_extract_field(
                                                    iv_content = iv_content
                                                    iv_offset  = zcl_csb43_constants=>c_f_credit_amount_offset
                                                    iv_length  = zcl_csb43_constants=>c_f_credit_amount_length )
                                                iv_debit_credit = zcl_csb43_constants=>c_credit_indicator ).

    DATA(wl_debit_amount) = iv_convert_amount( iv_amount_str   = iv_extract_field(
                                                   iv_content = iv_content
                                                   iv_offset  = zcl_csb43_constants=>c_f_debit_amount_offset
                                                   iv_length  = zcl_csb43_constants=>c_f_debit_amount_length )
                                               iv_debit_credit = zcl_csb43_constants=>c_debit_indicator ).

    wl_closing_indicator = iv_extract_field( iv_content = iv_content
                                             iv_offset  = zcl_csb43_constants=>c_f_closing_balance_ind
                                             iv_length  = 1 ).

    DATA(wl_closing_balance) = iv_convert_amount( iv_amount_str   = iv_extract_field(
                                                      iv_content = iv_content
                                                      iv_offset  = zcl_csb43_constants=>c_f_closing_balance_offset
                                                      iv_length  = zcl_csb43_constants=>c_f_closing_balance_length )
                                                  iv_debit_credit = wl_closing_indicator ).

    IF     abs( is_ebs-totalcreditamtinbkacctcr - wl_credit_amount ) < c_tolerance
       AND abs( is_ebs-totaldebitamtinbkacctcrc - wl_debit_amount )  < c_tolerance
       AND abs( is_ebs-clsgbalamtinbkacctcrcy - wl_closing_balance ) < c_tolerance.
      rv_valid = abap_true.
    ELSE.
      rv_valid = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD iv_extract_field.
    IF strlen( iv_content ) >= iv_offset + iv_length.
      rv_field = iv_content+iv_offset(iv_length).
    ENDIF.
  ENDMETHOD.


  METHOD iv_convert_amount.
    rv_amount = CONV ty_febep-amountinbankaccountcurrency( iv_amount_str ) / 100.

    IF iv_debit_credit = zcl_csb43_constants=>c_debit_indicator.
      rv_amount = rv_amount * -1.
    ENDIF.
  ENDMETHOD.


  METHOD iv_generate_uuid.
    TRY.
        rv_uuid = to_upper( cl_uuid_factory=>create_system_uuid( )->create_uuid_x16( ) ).
      CATCH cx_uuid_error.
        GET TIME STAMP FIELD DATA(wl_timestamp).
        rv_uuid = wl_timestamp.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
