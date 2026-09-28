*&---------------------------------------------------------------------*
*& Clase ZCL_BANKSTATEMENT_OPEN_ITEMS - Matching de partidas abiertas
*&---------------------------------------------------------------------*
*& Combinaciones multi-partida (subset-sum) optimizadas. SIN LLAMADORES
*& a fecha 2026-07: candidata a borrado o a integrarse en el flujo.
*&---------------------------------------------------------------------*
CLASS zcl_bankstatement_open_items DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_open_item,
        companycode            TYPE bukrs,
        accountingdocument     TYPE belnr_d,
        fiscalyear             TYPE gjahr,
        accountingdocumentitem TYPE buzei,
        customer               TYPE kunnr,
        supplier               TYPE lifnr,
        glaccount              TYPE hkont,
        documentdate           TYPE bldat,
        postingdate            TYPE budat,
        netduedate             TYPE dzfbdt,
        amountincompanycodeccy TYPE wrbtr,
        companycodecurrency    TYPE waers,
        paymentterms           TYPE dzterm,
        assignmentreference    TYPE dzuonr,
        documentitemtext       TYPE sgtxt,
        debitcreditcode        TYPE shkzg,
        specialglcode          TYPE i_operationalacctgdocitem-specialglcode,
        calculatednetduedate   TYPE datum,
        selected               TYPE abap_boolean,
      END OF ty_open_item,
      tty_open_item        TYPE STANDARD TABLE OF ty_open_item WITH EMPTY KEY,
      tty_open_item_hashed TYPE HASHED TABLE OF ty_open_item
        WITH UNIQUE KEY companycode accountingdocument fiscalyear accountingdocumentitem.

    " NEW: Types for multiple solutions
    TYPES tty_solution_set  TYPE STANDARD TABLE OF ty_open_item WITH EMPTY KEY.
    TYPES tty_all_solutions TYPE STANDARD TABLE OF tty_solution_set WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_search_config,
        item_type         TYPE c LENGTH 1, " D=Customer, K=Supplier, S=GL
        months_back       TYPE i,
        days_back         TYPE i,
        date_from         TYPE datum,
        date_to           TYPE datum,
        max_items         TYPE i,
        matching_strategy TYPE c LENGTH 1, " F=FIFO, L=LIFO, N=None (report multiple)
      END OF ty_search_config.

    TYPES: BEGIN OF ty_match_result,
             bank_amount     TYPE wrbtr,
             matched_amount  TYPE wrbtr,
             difference      TYPE wrbtr,
             matched_items   TYPE tty_open_item,
             match_quality   TYPE p LENGTH 3 DECIMALS 2,
             processing_time TYPE i,
           END OF ty_match_result.
    TYPES ty_quality TYPE p LENGTH 3 DECIMALS 2.

    TYPES:
      BEGIN OF ty_customer_batch_request,
        request_id  TYPE sysuuid_x16,
        customer    TYPE kunnr,
        companycode TYPE bukrs,
        amount      TYPE wrbtr,
        currency    TYPE waers,
        tolerance   TYPE p LENGTH 5 DECIMALS 2,
      END OF ty_customer_batch_request,
      tty_customer_batch_request TYPE STANDARD TABLE OF ty_customer_batch_request
        WITH NON-UNIQUE KEY customer companycode.

    TYPES:
      BEGIN OF ty_supplier_batch_request,
        request_id  TYPE sysuuid_x16,
        supplier    TYPE lifnr,
        companycode TYPE bukrs,
        amount      TYPE wrbtr,
        currency    TYPE waers,
        tolerance   TYPE p LENGTH 5 DECIMALS 2,
      END OF ty_supplier_batch_request,
      tty_supplier_batch_request TYPE STANDARD TABLE OF ty_supplier_batch_request
        WITH NON-UNIQUE KEY supplier companycode.

    TYPES:
      BEGIN OF ty_batch_result,
        request_id         TYPE sysuuid_x16,
        partner            TYPE c LENGTH 10,
        partner_type       TYPE c LENGTH 1,
        amount             TYPE wrbtr,
        matched_items      TYPE tty_open_item,
        total_matched      TYPE i,
        best_match         TYPE ty_open_item,
        exact_match        TYPE abap_boolean,
        match_quality      TYPE p LENGTH 3 DECIMALS 2,
        processing_time    TYPE i,
        multiple_solutions TYPE abap_boolean,          " NEW
        solution_count     TYPE i,                     " NEW
        all_solutions      TYPE tty_all_solutions,     " NEW
      END OF ty_batch_result,
      tty_batch_result TYPE STANDARD TABLE OF ty_batch_result WITH NON-UNIQUE KEY request_id.

    TYPES tr_customer    TYPE RANGE OF kunnr.
    TYPES tr_supplier    TYPE RANGE OF lifnr.
    TYPES tr_glaccount   TYPE RANGE OF hkont.
    TYPES tr_amount      TYPE RANGE OF wrbtr.
    TYPES tr_currency    TYPE RANGE OF waers.
    TYPES tr_date        TYPE RANGE OF datum.
    TYPES tr_companycode TYPE RANGE OF bukrs.

    INTERFACES if_oo_adt_classrun.

    METHODS ip_search_customer_items_batch
      IMPORTING it_requests       TYPE tty_customer_batch_request
                is_config         TYPE ty_search_config OPTIONAL
      RETURNING VALUE(rt_results) TYPE tty_batch_result.

    METHODS ip_search_supplier_items_batch
      IMPORTING it_requests       TYPE tty_supplier_batch_request
                is_config         TYPE ty_search_config OPTIONAL
      RETURNING VALUE(rt_results) TYPE tty_batch_result.

    METHODS ip_search_universal_batch
      IMPORTING it_customer_requests TYPE tty_customer_batch_request OPTIONAL
                it_supplier_requests TYPE tty_supplier_batch_request OPTIONAL
                is_config            TYPE ty_search_config           OPTIONAL
      RETURNING VALUE(rt_results)    TYPE tty_batch_result.

    METHODS ip_search_customer_items
      IMPORTING iv_customer     TYPE kunnr
                iv_companycode  TYPE bukrs
                iv_currency     TYPE waers            OPTIONAL
                is_config       TYPE ty_search_config OPTIONAL
      RETURNING VALUE(rt_items) TYPE tty_open_item.

    METHODS ip_search_supplier_items
      IMPORTING iv_supplier     TYPE lifnr
                iv_companycode  TYPE bukrs
                iv_currency     TYPE waers            OPTIONAL
                is_config       TYPE ty_search_config OPTIONAL
      RETURNING VALUE(rt_items) TYPE tty_open_item.

    METHODS ip_search_gl_items
      IMPORTING iv_glaccount    TYPE hkont
                iv_companycode  TYPE bukrs
                iv_currency     TYPE waers            OPTIONAL
                is_config       TYPE ty_search_config OPTIONAL
      RETURNING VALUE(rt_items) TYPE tty_open_item.

    METHODS ip_find_best_match
      IMPORTING iv_target_amount     TYPE wrbtr
                it_available_items   TYPE tty_open_item
                iv_tolerance_percent TYPE p DEFAULT '0.05'
                iv_max_time_ms       TYPE i DEFAULT 3000
      RETURNING VALUE(rs_result)     TYPE ty_match_result.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_payment_cache,
             paymentterms   TYPE dzterm,
             netpaymentdays TYPE i,
           END OF ty_payment_cache.

    DATA go_out           TYPE REF TO if_oo_adt_classrun_out.

    DATA gt_payment_cache TYPE HASHED TABLE OF ty_payment_cache WITH UNIQUE KEY paymentterms.

    TYPES: BEGIN OF ty_gl_oim_cache,
             companycode     TYPE bukrs,
             chartofaccounts TYPE ktopl,
             glaccount       TYPE hkont,
             has_oim         TYPE abap_boolean,
           END OF ty_gl_oim_cache.

    DATA gt_gl_oim_cache TYPE HASHED TABLE OF ty_gl_oim_cache
                         WITH UNIQUE KEY companycode chartofaccounts glaccount.

    METHODS iv_build_customer_range
      IMPORTING it_requests     TYPE tty_customer_batch_request
      RETURNING VALUE(rt_range) TYPE tr_customer.

    METHODS iv_build_supplier_range
      IMPORTING it_requests     TYPE tty_supplier_batch_request
      RETURNING VALUE(rt_range) TYPE tr_supplier.

    METHODS iv_build_amount_range_batch
      IMPORTING it_customer_requests TYPE tty_customer_batch_request OPTIONAL
                it_supplier_requests TYPE tty_supplier_batch_request OPTIONAL
      RETURNING VALUE(rt_range)      TYPE tr_amount.

    METHODS iv_build_currency_range
      IMPORTING it_customer_requests TYPE tty_customer_batch_request OPTIONAL
                it_supplier_requests TYPE tty_supplier_batch_request OPTIONAL
      RETURNING VALUE(rt_range)      TYPE tr_currency.

    METHODS iv_process_batch_results
      IMPORTING it_requests       TYPE tty_customer_batch_request OPTIONAL
                it_all_items      TYPE tty_open_item
                iv_partner_type   TYPE c                          DEFAULT 'D'
                is_config         TYPE ty_search_config           OPTIONAL  " ← AÑADIR ESTO
      RETURNING VALUE(rt_results) TYPE tty_batch_result.

    METHODS iv_get_payment_days
      IMPORTING iv_paymentterms TYPE dzterm
      RETURNING VALUE(rv_days)  TYPE i.

    METHODS iv_check_gl_open_item_mgmt
      IMPORTING iv_companycode    TYPE bukrs
                iv_glaccount      TYPE hkont
      RETURNING VALUE(rv_has_oim) TYPE abap_boolean.

    METHODS iv_handle_net_amounts
      CHANGING  ct_items        TYPE tty_open_item
      RETURNING VALUE(rv_count) TYPE i.

    METHODS iv_calculate_net_due_dates
      CHANGING ct_items TYPE tty_open_item.

    METHODS iv_add_days_to_date
      IMPORTING iv_date          TYPE datum
                iv_days          TYPE i
      RETURNING VALUE(rv_result) TYPE datum.

    METHODS iv_subtract_months
      IMPORTING iv_months      TYPE i
      RETURNING VALUE(rv_date) TYPE datum.

    METHODS iv_dp_subset_sum
      IMPORTING iv_target            TYPE wrbtr
                it_items             TYPE tty_open_item
                iv_tolerance_percent TYPE p
      RETURNING VALUE(rt_selected)   TYPE tty_open_item.

    METHODS iv_find_best_match_optimized
      IMPORTING iv_target_amount     TYPE wrbtr
                it_available_items   TYPE tty_open_item
                iv_tolerance_percent TYPE p DEFAULT '0.05'
                iv_max_time_ms       TYPE i DEFAULT 3000
      RETURNING VALUE(rs_result)     TYPE ty_match_result.

    METHODS iv_find_two_item_combination
      IMPORTING iv_target             TYPE wrbtr
                it_items              TYPE tty_open_item
                iv_tolerance          TYPE wrbtr
      RETURNING VALUE(rt_combination) TYPE tty_open_item.

    METHODS iv_find_three_item_combination
      IMPORTING iv_target             TYPE wrbtr
                it_items              TYPE tty_open_item
                iv_tolerance          TYPE wrbtr
      RETURNING VALUE(rt_combination) TYPE tty_open_item.

    METHODS iv_find_four_item_combination
      IMPORTING iv_target             TYPE wrbtr
                it_items              TYPE tty_open_item
                iv_tolerance          TYPE wrbtr
      RETURNING VALUE(rt_combination) TYPE tty_open_item.

    METHODS iv_greedy_subset_sum
      IMPORTING iv_target          TYPE wrbtr
                it_items           TYPE tty_open_item
                iv_tolerance       TYPE wrbtr
      RETURNING VALUE(rt_selected) TYPE tty_open_item.

    METHODS iv_calculate_match_quality
      IMPORTING iv_target         TYPE wrbtr
                iv_matched        TYPE wrbtr
      RETURNING VALUE(rv_quality) TYPE ty_quality.

    METHODS iv_dp_subset_sum_optimized
      IMPORTING iv_target            TYPE wrbtr
                it_items             TYPE tty_open_item
                iv_tolerance_percent TYPE p
                io_out               TYPE REF TO if_oo_adt_classrun_out OPTIONAL
      RETURNING VALUE(rt_selected)   TYPE tty_open_item.

    TYPES tty_solutions TYPE STANDARD TABLE OF tty_open_item WITH EMPTY KEY.

    METHODS iv_find_all_solutions
      IMPORTING iv_target            TYPE wrbtr
                it_items             TYPE tty_open_item
                iv_tolerance_percent TYPE p
                iv_max_solutions     TYPE i DEFAULT 100
      RETURNING VALUE(rt_solutions)  TYPE tty_solutions.

    "! Apply matching strategy (FIFO, LIFO, or None)
    METHODS iv_apply_matching_strategy
      IMPORTING it_solutions       TYPE tty_all_solutions
                iv_strategy        TYPE c
      RETURNING VALUE(rs_selected) TYPE tty_open_item.

    "! Compare two solutions to check if they are equivalent (same amounts)
    METHODS iv_are_solutions_equivalent
      IMPORTING it_solution1         TYPE tty_open_item
                it_solution2         TYPE tty_open_item
      RETURNING VALUE(rv_equivalent) TYPE abap_boolean.

    "! Safe UUID wrapper (swallows CX_UUID_ERROR)
    CLASS-METHODS iv_safe_uuid
      RETURNING VALUE(rv_uuid) TYPE sysuuid_x16.

ENDCLASS.



CLASS ZCL_BANKSTATEMENT_OPEN_ITEMS IMPLEMENTATION.


  METHOD ip_search_customer_items_batch.
    DATA: tl_all_items TYPE tty_open_item,
          wl_date_from TYPE datum,
          wl_date_to   TYPE datum,
          xl_config    TYPE ty_search_config.

    CHECK it_requests IS NOT INITIAL.

    xl_config = COND #( WHEN is_config IS SUPPLIED THEN is_config
                        ELSE VALUE #( item_type = 'D'
                                      months_back = 6
                                      max_items = 10000
                                      matching_strategy = 'F' ) ).

    IF xl_config-date_from IS NOT INITIAL.
      wl_date_from = xl_config-date_from.
    ELSEIF xl_config-months_back IS NOT INITIAL.
      wl_date_from = iv_subtract_months( xl_config-months_back ).
    ELSE.
      wl_date_from = cl_abap_context_info=>get_system_date( ) - 180.
    ENDIF.

    wl_date_to = COND #( WHEN xl_config-date_to IS NOT INITIAL
                         THEN xl_config-date_to
                         ELSE cl_abap_context_info=>get_system_date( ) ).

    DATA(tl_customer_range) = iv_build_customer_range( it_requests ).
    DATA(tl_currency_range) = iv_build_currency_range( it_customer_requests = it_requests ).

    DATA tl_companycode_range TYPE tr_companycode.
    LOOP AT it_requests INTO DATA(xl_req) GROUP BY xl_req-companycode.
      APPEND VALUE #( sign = 'I' option = 'EQ' low = xl_req-companycode )
        TO tl_companycode_range.
    ENDLOOP.

    IF lines( tl_currency_range ) = 0.
      SELECT
        companycode,
        accountingdocument,
        fiscalyear,
        accountingdocumentitem,
        customer,
        documentdate,
        postingdate,
        netduedate,
        amountincompanycodecurrency AS amountincompanycodeccy,
        companycodecurrency,
        paymentterms,
        assignmentreference,
        documentitemtext,
        debitcreditcode,
        specialglcode
      FROM i_operationalacctgdocitem WITH PRIVILEGED ACCESS
      WHERE companycode                 IN @tl_companycode_range
        AND customer                    IN @tl_customer_range
        AND clearingdate                 = '00000000'
        AND clearingjournalentry         = ''
        AND netduedate                  >= @wl_date_from
        AND netduedate                  <= @wl_date_to
        AND amountincompanycodecurrency  > 0
      ORDER BY customer, amountincompanycodecurrency
      INTO CORRESPONDING FIELDS OF TABLE @tl_all_items
      UP TO @xl_config-max_items ROWS.
    ELSE.
      SELECT
        companycode,
        accountingdocument,
        fiscalyear,
        accountingdocumentitem,
        customer,
        documentdate,
        postingdate,
        netduedate,
        amountincompanycodecurrency AS amountincompanycodeccy,
        companycodecurrency,
        paymentterms,
        assignmentreference,
        documentitemtext,
        debitcreditcode,
        specialglcode
      FROM i_operationalacctgdocitem WITH PRIVILEGED ACCESS
      WHERE companycode                 IN @tl_companycode_range
        AND customer                    IN @tl_customer_range
        AND clearingdate                 = '00000000'
        AND clearingjournalentry         = ''
        AND netduedate                  >= @wl_date_from
        AND netduedate                  <= @wl_date_to
        AND amountincompanycodecurrency  > 0
        AND companycodecurrency         IN @tl_currency_range
      ORDER BY customer, amountincompanycodecurrency
      INTO CORRESPONDING FIELDS OF TABLE @tl_all_items
      UP TO @xl_config-max_items ROWS.
    ENDIF.

    iv_handle_net_amounts( CHANGING ct_items = tl_all_items ).
    iv_calculate_net_due_dates( CHANGING ct_items = tl_all_items ).

    rt_results = iv_process_batch_results(
      it_requests     = it_requests
      it_all_items    = tl_all_items
      iv_partner_type = 'D'
      is_config       = xl_config ).

  ENDMETHOD.


  METHOD ip_search_supplier_items_batch.
    DATA: tl_all_items TYPE tty_open_item,
          wl_date_from TYPE datum,
          wl_date_to   TYPE datum,
          xl_config    TYPE ty_search_config.

    CHECK it_requests IS NOT INITIAL.

    xl_config = COND #( WHEN is_config IS SUPPLIED THEN is_config
                        ELSE VALUE #( item_type = 'K'
                                      days_back = 15
                                      max_items = 10000
                                      matching_strategy = 'F' ) ).

    IF xl_config-date_from IS NOT INITIAL.
      wl_date_from = xl_config-date_from.
    ELSEIF xl_config-days_back IS NOT INITIAL.
      wl_date_from = cl_abap_context_info=>get_system_date( ) - xl_config-days_back.
    ELSE.
      wl_date_from = cl_abap_context_info=>get_system_date( ) - 15.
    ENDIF.

    wl_date_to = COND #( WHEN xl_config-date_to IS NOT INITIAL
                         THEN xl_config-date_to
                         ELSE cl_abap_context_info=>get_system_date( ) ).

    DATA(tl_supplier_range) = iv_build_supplier_range( it_requests ).
    DATA(tl_currency_range) = iv_build_currency_range( it_supplier_requests = it_requests ).

    DATA tl_companycode_range TYPE tr_companycode.
    LOOP AT it_requests INTO DATA(xl_req) GROUP BY xl_req-companycode.
      APPEND VALUE #( sign = 'I' option = 'EQ' low = xl_req-companycode )
        TO tl_companycode_range.
    ENDLOOP.

    IF lines( tl_currency_range ) = 0.
      SELECT
        companycode,
        accountingdocument,
        fiscalyear,
        accountingdocumentitem,
        supplier,
        documentdate,
        postingdate,
        netduedate,
        amountincompanycodecurrency AS amountincompanycodeccy,
        companycodecurrency,
        paymentterms,
        assignmentreference,
        documentitemtext,
        debitcreditcode,
        specialglcode
      FROM i_operationalacctgdocitem WITH PRIVILEGED ACCESS
      WHERE companycode                 IN @tl_companycode_range
        AND supplier                    IN @tl_supplier_range
        AND clearingdate                 = '00000000'
        AND clearingjournalentry         = ''
        AND netduedate                  >= @wl_date_from
        AND netduedate                  <= @wl_date_to
        AND amountincompanycodecurrency  > 0
      ORDER BY supplier, amountincompanycodecurrency
      INTO CORRESPONDING FIELDS OF TABLE @tl_all_items
      UP TO @xl_config-max_items ROWS.
    ELSE.
      SELECT
        companycode,
        accountingdocument,
        fiscalyear,
        accountingdocumentitem,
        supplier,
        documentdate,
        postingdate,
        netduedate,
        amountincompanycodecurrency AS amountincompanycodeccy,
        companycodecurrency,
        paymentterms,
        assignmentreference,
        documentitemtext,
        debitcreditcode,
        specialglcode
      FROM i_operationalacctgdocitem WITH PRIVILEGED ACCESS
      WHERE companycode                 IN @tl_companycode_range
        AND supplier                    IN @tl_supplier_range
        AND clearingdate                 = '00000000'
        AND clearingjournalentry         = ''
        AND netduedate                  >= @wl_date_from
        AND netduedate                  <= @wl_date_to
        AND amountincompanycodecurrency  > 0
        AND companycodecurrency         IN @tl_currency_range
      ORDER BY supplier, amountincompanycodecurrency
      INTO CORRESPONDING FIELDS OF TABLE @tl_all_items
      UP TO @xl_config-max_items ROWS.
    ENDIF.

    iv_handle_net_amounts( CHANGING ct_items = tl_all_items ).
    iv_calculate_net_due_dates( CHANGING ct_items = tl_all_items ).

    rt_results = iv_process_batch_results(
      it_requests     = it_requests
      it_all_items    = tl_all_items
      iv_partner_type = 'K'
      is_config       = xl_config ).

  ENDMETHOD.


  METHOD ip_search_universal_batch.
    DATA tl_customer_results TYPE tty_batch_result.
    DATA tl_supplier_results TYPE tty_batch_result.

    IF it_customer_requests IS NOT INITIAL.
      tl_customer_results = ip_search_customer_items_batch( it_requests = it_customer_requests
                                                            is_config   = is_config ).
    ENDIF.

    IF it_supplier_requests IS NOT INITIAL.
      tl_supplier_results = ip_search_supplier_items_batch( it_requests = it_supplier_requests
                                                            is_config   = is_config ).
    ENDIF.

    rt_results = tl_customer_results.
    APPEND LINES OF tl_supplier_results TO rt_results.
  ENDMETHOD.


  METHOD ip_search_customer_items.
    DATA tl_request TYPE tty_customer_batch_request.

    APPEND VALUE #( request_id  = iv_safe_uuid( )
                    customer    = iv_customer
                    companycode = iv_companycode
                    amount      = 0
                    currency    = iv_currency
                    tolerance   = 1 )
           TO tl_request.

    DATA(tl_results) = ip_search_customer_items_batch( it_requests = tl_request
                                                       is_config   = is_config ).

    IF tl_results IS NOT INITIAL.
      rt_items = tl_results[ 1 ]-matched_items.
    ENDIF.
  ENDMETHOD.


  METHOD ip_search_supplier_items.
    DATA tl_request TYPE tty_supplier_batch_request.

    APPEND VALUE #( request_id  = iv_safe_uuid( )
                    supplier    = iv_supplier
                    companycode = iv_companycode
                    amount      = 0
                    currency    = iv_currency
                    tolerance   = 1 )
           TO tl_request.

    DATA(tl_results) = ip_search_supplier_items_batch( it_requests = tl_request
                                                       is_config   = is_config ).

    IF tl_results IS NOT INITIAL.
      rt_items = tl_results[ 1 ]-matched_items.
    ENDIF.
  ENDMETHOD.


  METHOD ip_search_gl_items.
    DATA wl_date_from TYPE datum.
    DATA wl_date_to   TYPE datum.
    DATA xl_config    TYPE ty_search_config.

    IF iv_check_gl_open_item_mgmt( iv_companycode = iv_companycode
                                   iv_glaccount   = iv_glaccount ) = abap_false.
      RETURN.
    ENDIF.

    xl_config = COND #( WHEN is_config IS SUPPLIED
                        THEN is_config
                        ELSE VALUE #( item_type   = 'S'
                                      months_back = 6
                                      max_items   = 1000 ) ).

    IF xl_config-date_from IS NOT INITIAL.
      wl_date_from = xl_config-date_from.
    ELSEIF xl_config-months_back IS NOT INITIAL.
      wl_date_from = iv_subtract_months( xl_config-months_back ).
    ELSE.
      wl_date_from = cl_abap_context_info=>get_system_date( ) - 180.
    ENDIF.

    wl_date_to = COND #( WHEN xl_config-date_to IS NOT INITIAL
                         THEN xl_config-date_to
                         ELSE cl_abap_context_info=>get_system_date( ) ).

    SELECT companycode,
           accountingdocument,
           fiscalyear,
           accountingdocumentitem,
           glaccount,
           documentdate,
           postingdate,
           netduedate,
           amountincompanycodecurrency AS amountincompanycodeccy,
           companycodecurrency,
           paymentterms,
           assignmentreference,
           documentitemtext,
           debitcreditcode,
           specialglcode
      FROM i_operationalacctgdocitem WITH
      PRIVILEGED ACCESS
      WHERE companycode           = @iv_companycode
        AND glaccount             = @iv_glaccount
        AND clearingdate          = '00000000'
        AND clearingjournalentry  = ''
        AND netduedate           >= @wl_date_from
        AND netduedate           <= @wl_date_to
        AND ( @iv_currency IS INITIAL OR companycodecurrency = @iv_currency )
      ORDER BY postingdate ASCENDING
      INTO CORRESPONDING FIELDS OF TABLE @rt_items
      UP TO @xl_config-max_items ROWS.

    iv_handle_net_amounts( CHANGING ct_items = rt_items ).
    iv_calculate_net_due_dates( CHANGING ct_items = rt_items ).

    SORT rt_items BY calculatednetduedate ASCENDING.
  ENDMETHOD.


  METHOD iv_check_gl_open_item_mgmt.
    LOOP AT gt_gl_oim_cache INTO DATA(ls_cache)
         WHERE     companycode = iv_companycode
               AND glaccount   = iv_glaccount. "#EC CI_HASHSEQ
      rv_has_oim = ls_cache-has_oim.
      RETURN.
    ENDLOOP.

    SELECT SINGLE glaccount, isopenitemmanaged
      FROM i_glaccountincompanycode WITH
      PRIVILEGED ACCESS
      WHERE companycode = @iv_companycode
        AND glaccount   = @iv_glaccount
      INTO @DATA(xl_gl_account).

    rv_has_oim = xsdbool(     sy-subrc = 0
                          AND xl_gl_account-isopenitemmanaged = abap_true ).

    SELECT SINGLE chartofaccounts FROM i_companycode WITH
      PRIVILEGED ACCESS
      WHERE companycode = @iv_companycode
      INTO @DATA(wl_chartofaccounts).

    INSERT VALUE #( companycode     = iv_companycode
                    chartofaccounts = wl_chartofaccounts
                    glaccount       = iv_glaccount
                    has_oim         = rv_has_oim )
           INTO TABLE gt_gl_oim_cache.
  ENDMETHOD.


  METHOD iv_handle_net_amounts.
    DATA wl_delete_idx TYPE sy-tabix.
    " TODO: variable is assigned but never used (ABAP cleaner)
    DATA wl_modify_idx TYPE sy-tabix.

    rv_count = 0.

    LOOP AT ct_items ASSIGNING FIELD-SYMBOL(<fs_item>)
         WHERE assignmentreference IS NOT INITIAL.

      wl_delete_idx = sy-tabix.
      rv_count += 1.

      LOOP AT ct_items ASSIGNING FIELD-SYMBOL(<fs_net>)
           WHERE     accountingdocument = <fs_item>-assignmentreference
                 AND companycode        = <fs_item>-companycode
                 AND fiscalyear         = <fs_item>-fiscalyear.

        wl_modify_idx = sy-tabix.

        DATA(wl_amount1) = COND wrbtr(
          WHEN <fs_item>-debitcreditcode = 'S'
          THEN <fs_item>-amountincompanycodeccy
          ELSE <fs_item>-amountincompanycodeccy * -1 ).

        DATA(wl_amount2) = COND wrbtr(
          WHEN <fs_net>-debitcreditcode = 'S'
          THEN <fs_net>-amountincompanycodeccy
          ELSE <fs_net>-amountincompanycodeccy * -1 ).

        DATA(wl_net_amount) = CONV wrbtr( wl_amount1 + wl_amount2 ).

        <fs_net>-amountincompanycodeccy = abs( wl_net_amount ).
        <fs_net>-debitcreditcode        = COND #(
                 WHEN wl_net_amount < 0 THEN 'H' ELSE 'S' ).

        DELETE ct_items INDEX wl_delete_idx.
        EXIT.
      ENDLOOP.
    ENDLOOP.

    DELETE ct_items WHERE     assignmentreference IS INITIAL
                          AND debitcreditcode      = 'H'.
  ENDMETHOD.


  METHOD iv_calculate_net_due_dates.
    CHECK ct_items IS NOT INITIAL.

    LOOP AT ct_items ASSIGNING FIELD-SYMBOL(<fs_item>).
      DATA(wl_days) = iv_get_payment_days( <fs_item>-paymentterms ).

      <fs_item>-calculatednetduedate = COND #(
        WHEN wl_days > 0
        THEN iv_add_days_to_date( iv_date = <fs_item>-netduedate
                                  iv_days = wl_days )
        ELSE <fs_item>-netduedate ).
    ENDLOOP.
  ENDMETHOD.


  METHOD iv_get_payment_days.
    READ TABLE gt_payment_cache WITH KEY paymentterms = iv_paymentterms
         TRANSPORTING NO FIELDS.

    IF sy-subrc = 0.
      rv_days = gt_payment_cache[ paymentterms = iv_paymentterms ]-netpaymentdays.
      RETURN.
    ENDIF.

    SELECT SINGLE netpaymentdays FROM i_paymenttermsconditions WITH
      PRIVILEGED ACCESS
      WHERE paymentterms = @iv_paymentterms
      INTO @rv_days.

    IF sy-subrc = 0.
      INSERT VALUE #( paymentterms   = iv_paymentterms
                      netpaymentdays = rv_days )
             INTO TABLE gt_payment_cache.
    ENDIF.
  ENDMETHOD.


  METHOD iv_add_days_to_date.
    rv_result = iv_date + iv_days.
  ENDMETHOD.


  METHOD iv_subtract_months.
    rv_date = cl_abap_context_info=>get_system_date( ) - ( iv_months * 30 ).
  ENDMETHOD.


  METHOD iv_calculate_match_quality.
    DATA wl_diff TYPE p LENGTH 16 DECIMALS 2.

    CHECK iv_target <> 0.

    wl_diff = abs( iv_target - iv_matched ).
    rv_quality = 100 - ( ( wl_diff / abs( iv_target ) ) * 100 ).

    rv_quality = nmax( val1 = 0
                       val2 = nmin( val1 = rv_quality
                                    val2 = 100 ) ).
  ENDMETHOD.


  METHOD ip_find_best_match.
    " TODO: parameter IV_MAX_TIME_MS is never used (ABAP cleaner)

    DATA wl_start_time TYPE timestampl.

    CLEAR rs_result.
    IF iv_target_amount IS INITIAL OR it_available_items IS INITIAL.
      RETURN.
    ENDIF.

    GET TIME STAMP FIELD wl_start_time.

    DATA(tl_matched) = iv_dp_subset_sum_optimized( iv_target            = iv_target_amount
                                                   it_items             = it_available_items
                                                   iv_tolerance_percent = iv_tolerance_percent
                                                   io_out               = go_out ).

    rs_result-bank_amount    = iv_target_amount.
    rs_result-matched_items  = tl_matched.
    rs_result-matched_amount = REDUCE wrbtr( INIT sum = 0
                                             FOR item IN tl_matched
                                             NEXT sum = sum + item-amountincompanycodeccy ).
    rs_result-difference     = iv_target_amount - rs_result-matched_amount.
    rs_result-match_quality  = iv_calculate_match_quality( iv_target  = iv_target_amount
                                                           iv_matched = rs_result-matched_amount ).

    GET TIME STAMP FIELD DATA(wl_end_time).
    rs_result-processing_time = cl_abap_tstmp=>subtract( tstmp1 = wl_end_time
                                                         tstmp2 = wl_start_time ) * 1000.
  ENDMETHOD.


  METHOD iv_dp_subset_sum.
    DATA wl_target_cents TYPE i.
    DATA wl_tolerance    TYPE i.
    DATA wl_min_target   TYPE i.
    DATA wl_max_target   TYPE i.
    DATA wl_amount_cents TYPE i.
    DATA wl_prev_sum     TYPE i.
    DATA tl_dp           TYPE STANDARD TABLE OF abap_boolean.
    DATA tl_parent       TYPE STANDARD TABLE OF i.
    DATA tl_item_used    TYPE STANDARD TABLE OF i.

    wl_target_cents = iv_target * 100.
    wl_tolerance = abs( iv_target ) * iv_tolerance_percent * 100.
    wl_min_target = wl_target_cents - wl_tolerance.
    wl_max_target = wl_target_cents + wl_tolerance.

    DATA(wl_table_size) = wl_max_target + 1.
    DO wl_table_size TIMES.
      APPEND abap_false TO tl_dp.
      APPEND 0 TO tl_parent.
      APPEND 0 TO tl_item_used.
    ENDDO.

    tl_dp[ 1 ] = abap_true.

    DATA wl_item_idx TYPE i VALUE 0.
    LOOP AT it_items INTO DATA(xl_item).
      wl_item_idx += 1.
      wl_amount_cents = xl_item-amountincompanycodeccy * 100.

      DATA(wl_sum) = wl_max_target.
      WHILE wl_sum >= wl_amount_cents.
        wl_prev_sum = wl_sum - wl_amount_cents.

        IF wl_prev_sum >= 0 AND wl_prev_sum + 1 <= lines( tl_dp ).
          IF tl_dp[ wl_prev_sum + 1 ] = abap_true.
            IF wl_sum + 1 <= lines( tl_dp ).
              IF tl_dp[ wl_sum + 1 ] = abap_false.
                tl_dp[ wl_sum + 1 ] = abap_true.
                tl_parent[ wl_sum + 1 ] = wl_prev_sum.
                tl_item_used[ wl_sum + 1 ] = wl_item_idx.
              ENDIF.
            ENDIF.
          ENDIF.
        ENDIF.

        wl_sum -= 1.
      ENDWHILE.
    ENDLOOP.

    DATA(wl_best_sum) = 0.
    DATA(wl_best_diff) = abs( wl_target_cents ).

    wl_sum = wl_min_target.
    WHILE wl_sum <= wl_max_target.
      IF wl_sum >= 0 AND wl_sum + 1 <= lines( tl_dp ).
        IF tl_dp[ wl_sum + 1 ] = abap_true.
          DATA(wl_diff) = abs( wl_target_cents - wl_sum ).
          IF wl_diff < wl_best_diff.
            wl_best_diff = wl_diff.
            wl_best_sum = wl_sum.
          ENDIF.
        ENDIF.
      ENDIF.
      wl_sum += 1.
    ENDWHILE.

    IF wl_best_sum > 0.
      DATA tl_selected_indices TYPE STANDARD TABLE OF i.
      wl_sum = wl_best_sum.

      WHILE wl_sum > 0 AND wl_sum + 1 <= lines( tl_item_used ).
        DATA(wl_item_used) = tl_item_used[ wl_sum + 1 ].
        IF wl_item_used > 0.
          APPEND wl_item_used TO tl_selected_indices.
          wl_sum = tl_parent[ wl_sum + 1 ].
        ELSE.
          EXIT.
        ENDIF.
      ENDWHILE.

      LOOP AT tl_selected_indices INTO DATA(wl_idx).
        READ TABLE it_items INTO xl_item INDEX wl_idx.
        IF sy-subrc = 0.
          xl_item-selected = abap_true.
          APPEND xl_item TO rt_selected.
        ENDIF.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.


  METHOD iv_find_best_match_optimized.
    " TODO: parameter IV_MAX_TIME_MS is never used (ABAP cleaner)

    DATA wl_start_time TYPE timestampl.
    DATA tl_sorted     TYPE tty_open_item.
    DATA wl_tolerance  TYPE wrbtr.

    CONSTANTS gc_cent_tolerance TYPE wrbtr VALUE '0.01'.

    CLEAR rs_result.
    IF iv_target_amount IS INITIAL OR it_available_items IS INITIAL.
      RETURN.
    ENDIF.

    GET TIME STAMP FIELD wl_start_time.

    wl_tolerance = abs( iv_target_amount ) * iv_tolerance_percent.

    tl_sorted = it_available_items.
    SORT tl_sorted BY amountincompanycodeccy DESCENDING.

    " STRATEGY 1: Try 2-item combinations
    DATA(tl_two_item_match) = iv_find_two_item_combination( iv_target    = iv_target_amount
                                                            it_items     = tl_sorted
                                                            iv_tolerance = wl_tolerance ).

    IF tl_two_item_match IS NOT INITIAL.
      rs_result-matched_items  = tl_two_item_match.
      rs_result-matched_amount = REDUCE wrbtr( INIT sum = 0
                                               FOR item IN tl_two_item_match
                                               NEXT sum = sum + item-amountincompanycodeccy ).
      rs_result-difference     = iv_target_amount - rs_result-matched_amount.

      IF abs( rs_result-difference ) < gc_cent_tolerance.
        rs_result-bank_amount   = iv_target_amount.
        rs_result-match_quality = 100.
        GET TIME STAMP FIELD DATA(wl_end_time).
        rs_result-processing_time = cl_abap_tstmp=>subtract( tstmp1 = wl_end_time
                                                             tstmp2 = wl_start_time ) * 1000.
        RETURN.
      ENDIF.
    ENDIF.

    " STRATEGY 2: Try 3-item combinations if n <= 50
    IF lines( tl_sorted ) <= 50.
      DATA(tl_three_item_match) = iv_find_three_item_combination( iv_target    = iv_target_amount
                                                                  it_items     = tl_sorted
                                                                  iv_tolerance = wl_tolerance ).

      IF tl_three_item_match IS NOT INITIAL.
        DATA(wl_three_sum) = REDUCE wrbtr( INIT sum = 0
                                            FOR item IN tl_three_item_match
                                            NEXT sum = sum + item-amountincompanycodeccy ).

        IF abs( iv_target_amount - wl_three_sum ) < gc_cent_tolerance.
          rs_result-matched_items  = tl_three_item_match.
          rs_result-matched_amount = wl_three_sum.
          rs_result-difference     = iv_target_amount - wl_three_sum.
          rs_result-bank_amount    = iv_target_amount.
          rs_result-match_quality  = 100.
          GET TIME STAMP FIELD wl_end_time.
          rs_result-processing_time = cl_abap_tstmp=>subtract( tstmp1 = wl_end_time
                                                               tstmp2 = wl_start_time ) * 1000.
          RETURN.
        ENDIF.
      ENDIF.
    ENDIF.

    " STRATEGY 3: Try 4-item combinations if n <= 30
    IF lines( tl_sorted ) <= 30.
      DATA(tl_four_item_match) = iv_find_four_item_combination( iv_target    = iv_target_amount
                                                                it_items     = tl_sorted
                                                                iv_tolerance = wl_tolerance ).

      IF tl_four_item_match IS NOT INITIAL.
        DATA(wl_four_sum) = REDUCE wrbtr( INIT sum = 0
                                           FOR item IN tl_four_item_match
                                           NEXT sum = sum + item-amountincompanycodeccy ).

        IF abs( iv_target_amount - wl_four_sum ) < gc_cent_tolerance.
          rs_result-matched_items  = tl_four_item_match.
          rs_result-matched_amount = wl_four_sum.
          rs_result-difference     = iv_target_amount - wl_four_sum.
          rs_result-bank_amount    = iv_target_amount.
          rs_result-match_quality  = 100.
          GET TIME STAMP FIELD wl_end_time.
          rs_result-processing_time = cl_abap_tstmp=>subtract( tstmp1 = wl_end_time
                                                               tstmp2 = wl_start_time ) * 1000.
          RETURN.
        ENDIF.
      ENDIF.
    ENDIF.

    " STRATEGY 4: Try greedy approach
    DATA(tl_greedy_match) = iv_greedy_subset_sum( iv_target    = iv_target_amount
                                                  it_items     = tl_sorted
                                                  iv_tolerance = wl_tolerance ).

    IF tl_greedy_match IS NOT INITIAL.
      DATA(wl_greedy_sum) = REDUCE wrbtr( INIT sum = 0
                                           FOR item IN tl_greedy_match
                                           NEXT sum = sum + item-amountincompanycodeccy ).

      IF abs( iv_target_amount - wl_greedy_sum ) < gc_cent_tolerance.
        rs_result-matched_items  = tl_greedy_match.
        rs_result-matched_amount = wl_greedy_sum.
        rs_result-difference     = iv_target_amount - wl_greedy_sum.
        rs_result-bank_amount    = iv_target_amount.
        rs_result-match_quality  = 100.
        GET TIME STAMP FIELD wl_end_time.
        rs_result-processing_time = cl_abap_tstmp=>subtract( tstmp1 = wl_end_time
                                                             tstmp2 = wl_start_time ) * 1000.
        RETURN.
      ENDIF.
    ENDIF.

    " STRATEGY 5: If n <= 20, use full DP
    IF lines( tl_sorted ) <= 20.
      DATA(tl_dp_match) = iv_dp_subset_sum_optimized(  " ← Changed here
                                                      iv_target            = iv_target_amount
                                                      it_items             = tl_sorted
                                                      iv_tolerance_percent = iv_tolerance_percent
                                                      io_out               = go_out ).

      IF tl_dp_match IS NOT INITIAL.
        rs_result-matched_items  = tl_dp_match.
        rs_result-matched_amount = REDUCE wrbtr( INIT sum = 0
                                                 FOR item IN tl_dp_match
                                                 NEXT sum = sum + item-amountincompanycodeccy ).
        rs_result-difference     = iv_target_amount - rs_result-matched_amount.
        rs_result-bank_amount    = iv_target_amount.
        rs_result-match_quality  = iv_calculate_match_quality( iv_target  = iv_target_amount
                                                               iv_matched = rs_result-matched_amount ).
        GET TIME STAMP FIELD wl_end_time.
        rs_result-processing_time = cl_abap_tstmp=>subtract( tstmp1 = wl_end_time
                                                             tstmp2 = wl_start_time ) * 1000.
        RETURN.
      ENDIF.
    ENDIF.

    " STRATEGY 6: Return best result found
    DATA wl_best_diff TYPE wrbtr VALUE 999999999.
    DATA tl_best      TYPE tty_open_item.

    IF tl_two_item_match IS NOT INITIAL.
      DATA(wl_two_diff) = CONV wrbtr( abs( rs_result-difference ) ).
      IF wl_two_diff < wl_best_diff.
        wl_best_diff = wl_two_diff.
        tl_best = tl_two_item_match.
      ENDIF.
    ENDIF.

    IF tl_three_item_match IS NOT INITIAL.
      DATA(wl_three_diff) = CONV wrbtr( abs( iv_target_amount - wl_three_sum ) ).
      IF wl_three_diff < wl_best_diff.
        wl_best_diff = wl_three_diff.
        tl_best = tl_three_item_match.
      ENDIF.
    ENDIF.

    IF tl_four_item_match IS NOT INITIAL.
      DATA(wl_four_diff) = CONV wrbtr( abs( iv_target_amount - wl_four_sum ) ).
      IF wl_four_diff < wl_best_diff.
        wl_best_diff = wl_four_diff.
        tl_best = tl_four_item_match.
      ENDIF.
    ENDIF.

    IF tl_greedy_match IS NOT INITIAL.
      DATA(wl_greedy_diff) = CONV wrbtr( abs( iv_target_amount - wl_greedy_sum ) ).
      IF wl_greedy_diff < wl_best_diff.
        wl_best_diff = wl_greedy_diff.
        tl_best = tl_greedy_match.
      ENDIF.
    ENDIF.

    IF tl_best IS NOT INITIAL.
      rs_result-matched_items  = tl_best.
      rs_result-matched_amount = REDUCE wrbtr( INIT sum = 0
                                               FOR item IN tl_best
                                               NEXT sum = sum + item-amountincompanycodeccy ).
      rs_result-difference     = iv_target_amount - rs_result-matched_amount.
      rs_result-bank_amount    = iv_target_amount.
      rs_result-match_quality  = iv_calculate_match_quality( iv_target  = iv_target_amount
                                                             iv_matched = rs_result-matched_amount ).
    ENDIF.

    GET TIME STAMP FIELD wl_end_time.
    rs_result-processing_time = cl_abap_tstmp=>subtract( tstmp1 = wl_end_time
                                                         tstmp2 = wl_start_time ) * 1000.
  ENDMETHOD.


  METHOD iv_find_two_item_combination.
    DATA wl_best_diff TYPE wrbtr VALUE 999999999.
    DATA wl_diff      TYPE wrbtr.
    DATA tl_best      TYPE tty_open_item.

    LOOP AT it_items INTO DATA(xl_item1).
      DATA(wl_idx1) = sy-tabix.
      LOOP AT it_items INTO DATA(xl_item2) FROM wl_idx1 + 1.
        DATA(wl_sum) = CONV wrbtr( xl_item1-amountincompanycodeccy + xl_item2-amountincompanycodeccy ).
        wl_diff = abs( iv_target - wl_sum ).

        IF wl_diff <= iv_tolerance AND wl_diff < wl_best_diff.
          wl_best_diff = wl_diff.
          CLEAR tl_best.
          APPEND xl_item1 TO tl_best.
          APPEND xl_item2 TO tl_best.

          IF wl_diff < '0.01'.
            rt_combination = tl_best.
            RETURN.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDLOOP.

    rt_combination = tl_best.
  ENDMETHOD.


  METHOD iv_find_three_item_combination.
    DATA wl_best_diff TYPE wrbtr VALUE 999999999.
    DATA wl_diff      TYPE wrbtr.
    DATA tl_best      TYPE tty_open_item.

    LOOP AT it_items INTO DATA(xl_item1).
      DATA(wl_idx1) = sy-tabix.
      LOOP AT it_items INTO DATA(xl_item2) FROM wl_idx1 + 1.
        DATA(wl_idx2) = sy-tabix.
        LOOP AT it_items INTO DATA(xl_item3) FROM wl_idx2 + 1.
          DATA(wl_sum) = CONV wrbtr( xl_item1-amountincompanycodeccy +
                         xl_item2-amountincompanycodeccy +
                         xl_item3-amountincompanycodeccy ).
          wl_diff = abs( iv_target - wl_sum ).

          IF wl_diff > iv_tolerance OR wl_diff >= wl_best_diff.
            CONTINUE.
          ENDIF.

          wl_best_diff = wl_diff.
          CLEAR tl_best.
          APPEND xl_item1 TO tl_best.
          APPEND xl_item2 TO tl_best.
          APPEND xl_item3 TO tl_best.

          IF wl_diff < '0.01'.
            rt_combination = tl_best.
            RETURN.
          ENDIF.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

    rt_combination = tl_best.
  ENDMETHOD.


  METHOD iv_find_four_item_combination.
    DATA wl_best_diff TYPE wrbtr VALUE 999999999.
    DATA wl_diff      TYPE wrbtr.
    DATA tl_best      TYPE tty_open_item.

    LOOP AT it_items INTO DATA(xl_item1).
      DATA(wl_idx1) = sy-tabix.
      LOOP AT it_items INTO DATA(xl_item2) FROM wl_idx1 + 1.
        DATA(wl_idx2) = sy-tabix.
        LOOP AT it_items INTO DATA(xl_item3) FROM wl_idx2 + 1.
          DATA(wl_idx3) = sy-tabix.
          LOOP AT it_items INTO DATA(xl_item4) FROM wl_idx3 + 1.
            DATA(wl_sum) = CONV wrbtr( xl_item1-amountincompanycodeccy +
                           xl_item2-amountincompanycodeccy +
                           xl_item3-amountincompanycodeccy +
                           xl_item4-amountincompanycodeccy ).
            wl_diff = abs( iv_target - wl_sum ).

            IF wl_diff > iv_tolerance OR wl_diff >= wl_best_diff.
              CONTINUE.
            ENDIF.

            wl_best_diff = wl_diff.
            CLEAR tl_best.
            APPEND xl_item1 TO tl_best.
            APPEND xl_item2 TO tl_best.
            APPEND xl_item3 TO tl_best.
            APPEND xl_item4 TO tl_best.

            IF wl_diff < '0.01'.
              rt_combination = tl_best.
              RETURN.
            ENDIF.
          ENDLOOP.
        ENDLOOP.
      ENDLOOP.
    ENDLOOP.

    rt_combination = tl_best.
  ENDMETHOD.


  METHOD iv_greedy_subset_sum.
    DATA wl_remaining TYPE wrbtr.
    DATA tl_selected  TYPE tty_open_item.
    DATA tl_sorted    TYPE tty_open_item.

    wl_remaining = iv_target.

    tl_sorted = it_items.
    SORT tl_sorted BY amountincompanycodeccy DESCENDING.

    LOOP AT tl_sorted INTO DATA(xl_item).
      IF xl_item-amountincompanycodeccy > wl_remaining + iv_tolerance.
        CONTINUE.
      ENDIF.

      APPEND xl_item TO tl_selected.
      wl_remaining = wl_remaining - xl_item-amountincompanycodeccy.

      IF abs( wl_remaining ) <= iv_tolerance.
        rt_selected = tl_selected.
        RETURN.
      ENDIF.

      IF wl_remaining < 0 AND abs( wl_remaining ) > iv_tolerance.
        DELETE tl_selected INDEX lines( tl_selected ).
        wl_remaining = wl_remaining + xl_item-amountincompanycodeccy.
      ENDIF.
    ENDLOOP.

    IF tl_selected IS NOT INITIAL.
      rt_selected = tl_selected.
    ENDIF.
  ENDMETHOD.


  METHOD iv_build_customer_range.
    LOOP AT it_requests INTO DATA(xl_req) GROUP BY xl_req-customer.
      APPEND VALUE #( sign   = 'I'
                      option = 'EQ'
                      low    = xl_req-customer ) TO rt_range.
    ENDLOOP.

    SORT rt_range BY low.
    DELETE ADJACENT DUPLICATES FROM rt_range COMPARING low.
  ENDMETHOD.


  METHOD iv_build_supplier_range.
    LOOP AT it_requests INTO DATA(xl_req) GROUP BY xl_req-supplier.
      APPEND VALUE #( sign   = 'I'
                      option = 'EQ'
                      low    = xl_req-supplier ) TO rt_range.
    ENDLOOP.

    SORT rt_range BY low.
    DELETE ADJACENT DUPLICATES FROM rt_range COMPARING low.
  ENDMETHOD.


  METHOD iv_build_amount_range_batch.
    " DEPRECATED: Amount range filtering removed to allow all possible combinations
    " Items are now filtered only by partner, company code, date, and currency
    " The matching algorithm handles finding the right combinations

    " Return empty range (not used anymore)
    CLEAR rt_range.

*    DATA wl_min_amount    TYPE wrbtr.
*    DATA wl_max_amount    TYPE wrbtr.
*    DATA wl_tolerance_abs TYPE wrbtr.
*
*    LOOP AT it_customer_requests INTO DATA(xl_cust_req).
*      IF xl_cust_req-amount > 0.
*        wl_tolerance_abs = abs( xl_cust_req-amount ) * xl_cust_req-tolerance.
*        wl_min_amount = xl_cust_req-amount - wl_tolerance_abs.
*        wl_max_amount = xl_cust_req-amount + wl_tolerance_abs.
*
*        APPEND VALUE #( sign   = 'I'
*                        option = 'BT'
*                        low    = wl_min_amount
*                        high   = wl_max_amount ) TO rt_range.
*      ENDIF.
*    ENDLOOP.
*
*    LOOP AT it_supplier_requests INTO DATA(xl_supp_req).
*      IF xl_supp_req-amount > 0.
*        wl_tolerance_abs = abs( xl_supp_req-amount ) * xl_supp_req-tolerance.
*        wl_min_amount = xl_supp_req-amount - wl_tolerance_abs.
*        wl_max_amount = xl_supp_req-amount + wl_tolerance_abs.
*
*        APPEND VALUE #( sign   = 'I'
*                        option = 'BT'
*                        low    = wl_min_amount
*                        high   = wl_max_amount ) TO rt_range.
*      ENDIF.
*    ENDLOOP.
*
*    IF rt_range IS INITIAL.
*      APPEND VALUE #( sign   = 'I'
*                      option = 'GT'
*                      low    = 0 ) TO rt_range.
*    ENDIF.
  ENDMETHOD.


  METHOD iv_build_currency_range.
    LOOP AT it_customer_requests INTO DATA(xl_cust) WHERE currency IS NOT INITIAL.
      APPEND VALUE #( sign   = 'I'
                      option = 'EQ'
                      low    = xl_cust-currency ) TO rt_range.
    ENDLOOP.

    LOOP AT it_supplier_requests INTO DATA(xl_supp) WHERE currency IS NOT INITIAL.
      APPEND VALUE #( sign   = 'I'
                      option = 'EQ'
                      low    = xl_supp-currency ) TO rt_range.
    ENDLOOP.

    SORT rt_range BY low.
    DELETE ADJACENT DUPLICATES FROM rt_range COMPARING low.
  ENDMETHOD.


METHOD iv_process_batch_results.
  DATA: tl_partner_items TYPE tty_open_item,
        wl_start_time    TYPE timestampl,
        xl_cust_request  TYPE ty_customer_batch_request,
        xl_supp_request  TYPE ty_supplier_batch_request.

  CONSTANTS: gc_cent_tolerance TYPE wrbtr VALUE '0.01'.

  DATA tl_items_by_partner TYPE SORTED TABLE OF ty_open_item
    WITH NON-UNIQUE KEY customer supplier amountincompanycodeccy.

  tl_items_by_partner = it_all_items.

  IF iv_partner_type = 'D'.
    " ========================================
    " CUSTOMER REQUESTS PROCESSING
    " ========================================
    LOOP AT it_requests INTO xl_cust_request.
      GET TIME STAMP FIELD wl_start_time.

      DATA(xl_result) = VALUE ty_batch_result(
        request_id   = xl_cust_request-request_id
        partner      = xl_cust_request-customer
        partner_type = 'D'
        amount       = xl_cust_request-amount
        multiple_solutions = abap_false
        solution_count = 0 ).

      CLEAR tl_partner_items.

      " Filter items for this customer
      LOOP AT tl_items_by_partner INTO DATA(xl_item)
        WHERE customer = xl_cust_request-customer
          AND companycode = xl_cust_request-companycode.

        IF xl_cust_request-currency IS NOT INITIAL
           AND xl_item-companycodecurrency <> xl_cust_request-currency.
          CONTINUE.
        ENDIF.

        APPEND xl_item TO tl_partner_items.
      ENDLOOP.

      xl_result-total_matched = lines( tl_partner_items ).

      IF xl_cust_request-amount > 0 AND tl_partner_items IS NOT INITIAL.

        " ALWAYS find all exact solutions first
        DATA(lt_all_solutions) = iv_find_all_solutions(
          iv_target            = xl_cust_request-amount
          it_items             = tl_partner_items
          iv_tolerance_percent = xl_cust_request-tolerance
          iv_max_solutions     = 100 ).

        IF lt_all_solutions IS NOT INITIAL.
          " If iv_find_all_solutions returned results, they are exact solutions by definition
          xl_result-exact_match = abap_true.

          " Get strategy from config
          DATA(lv_strategy) = COND #( WHEN is_config-matching_strategy IS NOT INITIAL
                                      THEN is_config-matching_strategy
                                      ELSE 'F' ).

          " Determine if multiple solutions exist
          DATA(lv_solution_count) = lines( lt_all_solutions ).
          xl_result-solution_count = lv_solution_count.
          xl_result-all_solutions = lt_all_solutions.

          IF lv_solution_count > 1.
            " Multiple unique solutions found
            xl_result-multiple_solutions = abap_true.

            " Apply strategy
            IF lv_strategy = 'N'.
              " No strategy - return first solution but flag multiple
              xl_result-matched_items = lt_all_solutions[ 1 ].
            ELSE.
              " Apply FIFO or LIFO strategy
              xl_result-matched_items = iv_apply_matching_strategy(
                it_solutions = lt_all_solutions
                iv_strategy  = lv_strategy ).
            ENDIF.

          ELSE.
            " Only one unique solution
            xl_result-multiple_solutions = abap_false.
            xl_result-matched_items = lt_all_solutions[ 1 ].
          ENDIF.

          " Calculate quality
          DATA(wl_matched_sum) = REDUCE wrbtr( INIT sum = 0
                                                FOR item IN xl_result-matched_items
                                                NEXT sum = sum + item-amountincompanycodeccy ).
          xl_result-match_quality = iv_calculate_match_quality(
            iv_target = xl_cust_request-amount
            iv_matched = wl_matched_sum ).

          " Set best_match to first item
          READ TABLE xl_result-matched_items INTO xl_result-best_match INDEX 1.

        ELSE.
          " No exact solutions found - try best approximation
          xl_result-exact_match = abap_false.

          DATA(ls_match_result) = iv_find_best_match_optimized(
            iv_target_amount     = xl_cust_request-amount
            it_available_items   = tl_partner_items
            iv_tolerance_percent = xl_cust_request-tolerance
            iv_max_time_ms       = 3000 ).

          IF ls_match_result-matched_items IS NOT INITIAL.
            xl_result-matched_items = ls_match_result-matched_items.

            wl_matched_sum = REDUCE wrbtr( INIT sum = 0
                                           FOR item IN xl_result-matched_items
                                           NEXT sum = sum + item-amountincompanycodeccy ).
            xl_result-match_quality = iv_calculate_match_quality(
              iv_target = xl_cust_request-amount
              iv_matched = wl_matched_sum ).

            " Check if approximation is exact
            IF abs( xl_cust_request-amount - wl_matched_sum ) < gc_cent_tolerance.
              xl_result-exact_match = abap_true.
            ENDIF.

            READ TABLE xl_result-matched_items INTO xl_result-best_match INDEX 1.

          ELSE.
            " Algorithm didn't find any solutions, find closest single item
            DATA(wl_best_diff) = CONV wrbtr( abs( xl_cust_request-amount ) ).
            LOOP AT tl_partner_items INTO DATA(xl_candidate).
              DATA(wl_diff) = CONV wrbtr( abs( xl_cust_request-amount - xl_candidate-amountincompanycodeccy ) ).
              IF wl_diff < wl_best_diff.
                wl_best_diff = wl_diff.
                xl_result-best_match = xl_candidate.
              ENDIF.
            ENDLOOP.

            IF xl_result-best_match IS NOT INITIAL.
              xl_result-matched_items = VALUE #( ( xl_result-best_match ) ).
              xl_result-match_quality = iv_calculate_match_quality(
                iv_target = xl_cust_request-amount
                iv_matched = xl_result-best_match-amountincompanycodeccy ).
            ENDIF.
          ENDIF.
        ENDIF.

      ELSE.
        " No specific amount requested, return all items
        xl_result-matched_items = tl_partner_items.
      ENDIF.

      GET TIME STAMP FIELD DATA(wl_end_time).
      xl_result-processing_time = cl_abap_tstmp=>subtract(
                                    tstmp1 = wl_end_time
                                    tstmp2 = wl_start_time ) * 1000.

      APPEND xl_result TO rt_results.
    ENDLOOP.

  ELSEIF iv_partner_type = 'K'.
    " ========================================
    " SUPPLIER REQUESTS PROCESSING
    " ========================================
    DATA lt_supplier_requests TYPE tty_supplier_batch_request.

    LOOP AT it_requests INTO DATA(xl_generic_req).
      APPEND CORRESPONDING #( xl_generic_req ) TO lt_supplier_requests.
    ENDLOOP.

    LOOP AT lt_supplier_requests INTO xl_supp_request.
      GET TIME STAMP FIELD wl_start_time.

      xl_result = VALUE ty_batch_result(
        request_id   = xl_supp_request-request_id
        partner      = xl_supp_request-supplier
        partner_type = 'K'
        amount       = xl_supp_request-amount
        multiple_solutions = abap_false
        solution_count = 0 ).

      CLEAR tl_partner_items.

      " Filter items for this supplier
      LOOP AT tl_items_by_partner INTO xl_item
        WHERE supplier = xl_supp_request-supplier
          AND companycode = xl_supp_request-companycode. "#EC CI_SORTSEQ

        IF xl_supp_request-currency IS NOT INITIAL
           AND xl_item-companycodecurrency <> xl_supp_request-currency.
          CONTINUE.
        ENDIF.

        APPEND xl_item TO tl_partner_items.
      ENDLOOP.

      xl_result-total_matched = lines( tl_partner_items ).

      IF xl_supp_request-amount > 0 AND tl_partner_items IS NOT INITIAL.

        " ALWAYS find all exact solutions first
        lt_all_solutions = iv_find_all_solutions(
          iv_target            = xl_supp_request-amount
          it_items             = tl_partner_items
          iv_tolerance_percent = xl_supp_request-tolerance
          iv_max_solutions     = 100 ).

        IF lt_all_solutions IS NOT INITIAL.
          " If iv_find_all_solutions returned results, they are exact solutions by definition
          xl_result-exact_match = abap_true.

          lv_strategy = COND #( WHEN is_config-matching_strategy IS NOT INITIAL
                                THEN is_config-matching_strategy
                                ELSE 'F' ).

          lv_solution_count = lines( lt_all_solutions ).
          xl_result-solution_count = lv_solution_count.
          xl_result-all_solutions = lt_all_solutions.

          IF lv_solution_count > 1.
            xl_result-multiple_solutions = abap_true.

            IF lv_strategy = 'N'.
              xl_result-matched_items = lt_all_solutions[ 1 ].
            ELSE.
              xl_result-matched_items = iv_apply_matching_strategy(
                it_solutions = lt_all_solutions
                iv_strategy  = lv_strategy ).
            ENDIF.

          ELSE.
            xl_result-multiple_solutions = abap_false.
            xl_result-matched_items = lt_all_solutions[ 1 ].
          ENDIF.

          wl_matched_sum = REDUCE wrbtr( INIT sum = 0
                                         FOR item IN xl_result-matched_items
                                         NEXT sum = sum + item-amountincompanycodeccy ).
          xl_result-match_quality = iv_calculate_match_quality(
            iv_target = xl_supp_request-amount
            iv_matched = wl_matched_sum ).

          READ TABLE xl_result-matched_items INTO xl_result-best_match INDEX 1.

        ELSE.
          " No exact solutions - try best approximation
          xl_result-exact_match = abap_false.

          ls_match_result = iv_find_best_match_optimized(
            iv_target_amount     = xl_supp_request-amount
            it_available_items   = tl_partner_items
            iv_tolerance_percent = xl_supp_request-tolerance
            iv_max_time_ms       = 3000 ).

          IF ls_match_result-matched_items IS NOT INITIAL.
            xl_result-matched_items = ls_match_result-matched_items.

            wl_matched_sum = REDUCE wrbtr( INIT sum = 0
                                           FOR item IN xl_result-matched_items
                                           NEXT sum = sum + item-amountincompanycodeccy ).
            xl_result-match_quality = iv_calculate_match_quality(
              iv_target = xl_supp_request-amount
              iv_matched = wl_matched_sum ).

            " Check if approximation is exact
            IF abs( xl_supp_request-amount - wl_matched_sum ) < gc_cent_tolerance.
              xl_result-exact_match = abap_true.
            ENDIF.

            READ TABLE xl_result-matched_items INTO xl_result-best_match INDEX 1.

          ELSE.
            " No solutions found, find closest single item
            wl_best_diff = abs( xl_supp_request-amount ).
            LOOP AT tl_partner_items INTO xl_candidate.
              wl_diff = abs( xl_supp_request-amount - xl_candidate-amountincompanycodeccy ).
              IF wl_diff < wl_best_diff.
                wl_best_diff = wl_diff.
                xl_result-best_match = xl_candidate.
              ENDIF.
            ENDLOOP.

            IF xl_result-best_match IS NOT INITIAL.
              xl_result-matched_items = VALUE #( ( xl_result-best_match ) ).
              xl_result-match_quality = iv_calculate_match_quality(
                iv_target = xl_supp_request-amount
                iv_matched = xl_result-best_match-amountincompanycodeccy ).
            ENDIF.
          ENDIF.
        ENDIF.

      ELSE.
        xl_result-matched_items = tl_partner_items.
      ENDIF.

      GET TIME STAMP FIELD wl_end_time.
      xl_result-processing_time = cl_abap_tstmp=>subtract(
                                    tstmp1 = wl_end_time
                                    tstmp2 = wl_start_time ) * 1000.

      APPEND xl_result TO rt_results.
    ENDLOOP.

  ENDIF.

ENDMETHOD.


  METHOD iv_dp_subset_sum_optimized.
    " Optimized Dynamic Programming for subset sum problem
    " Uses HASHED tables and early exit for better performance

    DATA wl_target_cents TYPE i.
    DATA wl_tolerance    TYPE i.
    DATA wl_min_target   TYPE i.
    DATA wl_max_target   TYPE i.
    DATA wl_amount_cents TYPE i.
    DATA wl_start_time   TYPE timestampl.
    DATA wl_current_time TYPE timestampl.
    DATA wl_elapsed_ms   TYPE i.

    " Optimized DP structure with hash table
    TYPES: BEGIN OF ty_dp_entry,
             sum        TYPE i,
             parent_sum TYPE i,
             item_index TYPE i,
             achievable TYPE abap_boolean,
           END OF ty_dp_entry.

    " HASHED TABLE for O(1) lookup instead of O(n)
    DATA tl_dp TYPE HASHED TABLE OF ty_dp_entry WITH UNIQUE KEY sum.

    GET TIME STAMP FIELD wl_start_time.

    " TRACE: Initial parameters
    IF io_out IS BOUND.
      io_out->write( |DP_OPT: Starting optimization| ).
      io_out->write( |  Target amount: { iv_target }| ).
      io_out->write( |  Tolerance: { iv_tolerance_percent * 100 }%| ).
      io_out->write( |  Items count: { lines( it_items ) }| ).
    ENDIF.

    " Convert to cents for integer arithmetic
    wl_target_cents = iv_target * 100.
    wl_tolerance = abs( iv_target ) * iv_tolerance_percent * 100.
    wl_min_target = wl_target_cents - wl_tolerance.
    wl_max_target = wl_target_cents + wl_tolerance.

    " TRACE: Range calculations
    IF io_out IS BOUND.
      io_out->write( |  Target range: { wl_min_target } - { wl_max_target } cents| ).
      io_out->write( |  Range width: { wl_max_target - wl_min_target } positions| ).
    ENDIF.

    " Initialize with sum 0 (always achievable)
    INSERT VALUE #( sum        = 0
                    achievable = abap_true ) INTO TABLE tl_dp.

    IF io_out IS BOUND.
      io_out->write( |DP_OPT: Starting item processing...| ).
    ENDIF.

    " Process each item
    DATA wl_item_idx TYPE i VALUE 0.
    LOOP AT it_items INTO DATA(xl_item).
      wl_item_idx += 1.
      wl_amount_cents = xl_item-amountincompanycodeccy * 100.

      " TRACE: Processing item
      IF io_out IS BOUND.
        io_out->write(
            |  Processing item { wl_item_idx }/{ lines( it_items ) }: { xl_item-amountincompanycodeccy } ({ wl_amount_cents } cents)| ).
      ENDIF.

      " Skip if item is larger than max target (optimization)
      IF wl_amount_cents > wl_max_target.
        IF io_out IS BOUND.
          io_out->write( |    SKIPPED: Amount larger than max target| ).
        ENDIF.
        CONTINUE.
      ENDIF.

      " Check timeout (30 seconds)
      GET TIME STAMP FIELD wl_current_time.
      wl_elapsed_ms = cl_abap_tstmp=>subtract( tstmp1 = wl_current_time
                                               tstmp2 = wl_start_time ) * 1000.
      IF wl_elapsed_ms > 30000.
        IF io_out IS BOUND.
          io_out->write( |DP_OPT: TIMEOUT after { wl_elapsed_ms } ms - Exiting early| ).
        ENDIF.
        RETURN. " Exit after 30 seconds
      ENDIF.

      " Temporary table for new sums (avoid modifying during loop)
      DATA tl_new_sums TYPE HASHED TABLE OF ty_dp_entry WITH UNIQUE KEY sum.

      DATA lv_loops    TYPE i VALUE 0.
      DATA lv_new_sums TYPE i VALUE 0.

      " Iterate over existing achievable sums
      LOOP AT tl_dp INTO DATA(ls_dp) WHERE achievable = abap_true. "#EC CI_HASHSEQ
        lv_loops = lv_loops + 1.
        DATA(wl_new_sum) = ls_dp-sum + wl_amount_cents.

        " Only process sums within target range (major optimization)
        IF wl_new_sum < wl_min_target OR wl_new_sum > wl_max_target.
          CONTINUE.
        ENDIF.

        " Check if this sum already exists
        READ TABLE tl_dp WITH KEY sum = wl_new_sum TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0.
          " New sum found - add to temporary table
          INSERT VALUE #( sum        = wl_new_sum
                          parent_sum = ls_dp-sum
                          item_index = wl_item_idx
                          achievable = abap_true )
                 INTO TABLE tl_new_sums.
          lv_new_sums = lv_new_sums + 1.
        ENDIF.
      ENDLOOP.

      " TRACE: Loop statistics
      IF io_out IS BOUND.
        io_out->write( |    Loops: { lv_loops }, New sums: { lv_new_sums }, Total DP entries: { lines( tl_dp ) }| ).
      ENDIF.

      " TRACE: Loop statistics
      IF io_out IS BOUND.
        io_out->write( |    Loops: { lv_loops }, New sums: { lv_new_sums }, Total DP entries: { lines( tl_dp ) }| ).
      ENDIF.

      " Add new sums to main DP table (handling duplicates)
      LOOP AT tl_new_sums INTO DATA(ls_new_entry).
        INSERT ls_new_entry INTO TABLE tl_dp.
        " Ignore sy-subrc - duplicates are OK and expected
      ENDLOOP.

      " TRACE: After insertion
      IF io_out IS BOUND.
        io_out->write( |    DP table size after insert: { lines( tl_dp ) }| ).
      ENDIF.

      " EARLY EXIT: If exact match found, stop processing
      READ TABLE tl_dp WITH KEY sum = wl_target_cents TRANSPORTING NO FIELDS.
      IF sy-subrc = 0.
        IF io_out IS BOUND.
          io_out->write( |DP_OPT: EXACT MATCH FOUND! Stopping early at item { wl_item_idx }| ).
        ENDIF.
        EXIT. " Found exact match - no need to continue
      ENDIF.

    ENDLOOP.

    GET TIME STAMP FIELD wl_current_time.
    wl_elapsed_ms = cl_abap_tstmp=>subtract( tstmp1 = wl_current_time
                                             tstmp2 = wl_start_time ) * 1000.

    IF io_out IS BOUND.
      io_out->write( |DP_OPT: Item processing complete| ).
      io_out->write( |  Time elapsed: { wl_elapsed_ms } ms| ).
      io_out->write( |  Final DP table size: { lines( tl_dp ) }| ).
      io_out->write( |DP_OPT: Finding best sum...| ).
    ENDIF.

    " Find best sum within tolerance range
    DATA(wl_best_sum) = 0.
    DATA(wl_best_diff) = abs( wl_target_cents ).

    LOOP AT tl_dp INTO ls_dp WHERE achievable = abap_true. "#EC CI_HASHSEQ
      IF ls_dp-sum >= wl_min_target AND ls_dp-sum <= wl_max_target.
        DATA(wl_diff) = abs( wl_target_cents - ls_dp-sum ).
        IF wl_diff < wl_best_diff.
          wl_best_diff = wl_diff.
          wl_best_sum = ls_dp-sum.
        ENDIF.
      ENDIF.
    ENDLOOP.

    IF io_out IS BOUND.
      io_out->write( |  Best sum found: { wl_best_sum } cents (diff: { wl_best_diff })| ).
    ENDIF.

    " Backtrack to find selected items
    IF wl_best_sum > 0.
      DATA tl_selected_indices TYPE STANDARD TABLE OF i.
      DATA wl_current_sum      TYPE i.

      wl_current_sum = wl_best_sum.

      IF io_out IS BOUND.
        io_out->write( |DP_OPT: Backtracking to find items...| ).
      ENDIF.

      " Trace back through parent sums to find items used
      WHILE wl_current_sum > 0.
        READ TABLE tl_dp WITH KEY sum = wl_current_sum INTO ls_dp.
        IF sy-subrc = 0 AND ls_dp-item_index > 0.
          APPEND ls_dp-item_index TO tl_selected_indices.
          IF io_out IS BOUND.
            io_out->write( |    Item { ls_dp-item_index } used, parent sum: { ls_dp-parent_sum }| ).
          ENDIF.
          wl_current_sum = ls_dp-parent_sum.
        ELSE.
          IF io_out IS BOUND.
            io_out->write( |    Backtrack stopped at sum { wl_current_sum }| ).
          ENDIF.
          EXIT. " No parent found - shouldn't happen but safety exit
        ENDIF.
      ENDWHILE.

      " Build result table with selected items
      IF io_out IS BOUND.
        io_out->write( |  Items in solution: { lines( tl_selected_indices ) }| ).
      ENDIF.

      LOOP AT tl_selected_indices INTO DATA(wl_idx).
        READ TABLE it_items INTO xl_item INDEX wl_idx.
        IF sy-subrc = 0.
          xl_item-selected = abap_true.
          APPEND xl_item TO rt_selected.
        ENDIF.
      ENDLOOP.
    ENDIF.

    GET TIME STAMP FIELD wl_current_time.
    wl_elapsed_ms = cl_abap_tstmp=>subtract( tstmp1 = wl_current_time
                                             tstmp2 = wl_start_time ) * 1000.

    IF io_out IS BOUND.
      io_out->write( |DP_OPT: Complete in { wl_elapsed_ms } ms| ).
    ENDIF.
  ENDMETHOD.


  METHOD iv_find_all_solutions.
    " Find ALL possible combinations that sum EXACTLY to target
    " Uses exhaustive search for <=25 items, optimized DP for larger sets

    DATA wl_target_cents TYPE i.
    DATA wl_start_time   TYPE timestampl.
    DATA wl_current_time TYPE timestampl.
    DATA wl_elapsed_ms   TYPE i.

    CONSTANTS gc_exact_tolerance      TYPE i VALUE 100.   " 1.00 AED tolerance
    CONSTANTS gc_max_items_exhaustive TYPE i VALUE 25.    " Increased limit
    CONSTANTS gc_timeout_ms           TYPE i VALUE 10000. " 10 second timeout

    wl_target_cents = iv_target * 100.
    GET TIME STAMP FIELD wl_start_time.

    DATA tl_all_solutions TYPE tty_all_solutions.
    DATA(lv_num_items) = lines( it_items ).

    " DEBUG
    IF go_out IS BOUND.
      go_out->write( |FIND_ALL_SOLUTIONS DEBUG:| ).
      go_out->write( |  Target: { iv_target } ({ wl_target_cents } cents)| ).
      go_out->write( |  Num items: { lv_num_items }| ).
      go_out->write( |  Tolerance: { gc_exact_tolerance } cents| ).
    ENDIF.

    " ============================================
    " EXHAUSTIVE SEARCH for small sets (<= 25 items)
    " ============================================
    IF lv_num_items <= gc_max_items_exhaustive.
      " Calculate max combinations (2^n)
      DATA lv_max_combo TYPE i VALUE 1.
      DATA lv_counter   TYPE i VALUE 0.
      WHILE lv_counter < lv_num_items.
        lv_max_combo = lv_max_combo * 2.
        lv_counter = lv_counter + 1.
      ENDWHILE.

      IF go_out IS BOUND.
        go_out->write( |  Using EXHAUSTIVE SEARCH| ).
        go_out->write( |  Max combinations to try: { lv_max_combo }| ).
      ENDIF.

      DATA tl_current_combo   TYPE tty_open_item.
      DATA lv_combo_sum_cents TYPE i.

      DATA lv_combos_tried    TYPE i             VALUE 0.
      DATA lv_exact_found     TYPE i             VALUE 0.

      " Try all combinations from 1 to 2^n - 1
      DATA lv_combo_num       TYPE i             VALUE 1.
      WHILE lv_combo_num < lv_max_combo.
        lv_combos_tried = lv_combos_tried + 1.

        " Check timeout every 1000 iterations
        IF lv_combos_tried MOD 1000 = 0.
          GET TIME STAMP FIELD wl_current_time.
          wl_elapsed_ms = cl_abap_tstmp=>subtract( tstmp1 = wl_current_time
                                                   tstmp2 = wl_start_time ) * 1000.
          IF wl_elapsed_ms > gc_timeout_ms.
            IF go_out IS BOUND.
              go_out->write( |  TIMEOUT after { wl_elapsed_ms } ms at combo { lv_combos_tried }| ).
            ENDIF.
            EXIT.
          ENDIF.
        ENDIF.

        CLEAR: tl_current_combo,
               lv_combo_sum_cents.

        " Build combination by testing each bit
        DATA lv_temp_num TYPE i.
        DATA lv_item_idx TYPE i.

        lv_temp_num = lv_combo_num.
        lv_item_idx = 1.

        WHILE lv_item_idx <= lv_num_items.
          IF lv_temp_num MOD 2 = 1.
            READ TABLE it_items INTO DATA(xl_item) INDEX lv_item_idx.
            IF sy-subrc = 0.
              APPEND xl_item TO tl_current_combo.
              lv_combo_sum_cents = lv_combo_sum_cents + ( xl_item-amountincompanycodeccy * 100 ).
            ENDIF.
          ENDIF.

          lv_temp_num = lv_temp_num DIV 2.
          lv_item_idx = lv_item_idx + 1.
        ENDWHILE.

        " Check if exact match
        DATA(wl_diff) = abs( wl_target_cents - lv_combo_sum_cents ).

        IF wl_diff <= gc_exact_tolerance AND tl_current_combo IS NOT INITIAL.
          lv_exact_found = lv_exact_found + 1.

          " Check if duplicate
          DATA lv_is_dup TYPE abap_boolean VALUE abap_false.

          LOOP AT tl_all_solutions INTO DATA(lt_existing_sol).
            IF iv_are_solutions_equivalent( it_solution1 = tl_current_combo
                                            it_solution2 = lt_existing_sol ) = abap_true.
              lv_is_dup = abap_true.
              EXIT.
            ENDIF.
          ENDLOOP.

          IF lv_is_dup = abap_false.
            APPEND tl_current_combo TO tl_all_solutions.

            IF lines( tl_all_solutions ) >= iv_max_solutions.
              IF go_out IS BOUND.
                go_out->write( |  MAX SOLUTIONS REACHED: { lines( tl_all_solutions ) }| ).
              ENDIF.
              rt_solutions = tl_all_solutions.
              RETURN.
            ENDIF.
          ENDIF.
        ENDIF.

        lv_combo_num = lv_combo_num + 1.
      ENDWHILE.

      GET TIME STAMP FIELD wl_current_time.
      wl_elapsed_ms = cl_abap_tstmp=>subtract( tstmp1 = wl_current_time
                                               tstmp2 = wl_start_time ) * 1000.

      IF go_out IS BOUND.
        go_out->write( |  Combinations tried: { lv_combos_tried }| ).
        go_out->write( |  Exact matches found: { lv_exact_found }| ).
        go_out->write( |  Unique solutions: { lines( tl_all_solutions ) }| ).
        go_out->write( |  Time elapsed: { wl_elapsed_ms } ms| ).
      ENDIF.

      rt_solutions = tl_all_solutions.
      RETURN.
    ENDIF.

    " ============================================
    " DYNAMIC PROGRAMMING for larger sets (> 25 items)
    " Using HASHED TABLES for O(1) lookup
    " ============================================
    IF go_out IS BOUND.
      go_out->write( |  Using DYNAMIC PROGRAMMING (Optimized with Hashed Tables)| ).
    ENDIF.

    " Optimized DP structure with HASHED table for fast lookup
    TYPES: BEGIN OF ty_dp_path,
             sum        TYPE i,
             items_used TYPE STANDARD TABLE OF i WITH EMPTY KEY,
           END OF ty_dp_path.

    " Use HASHED table indexed by sum for O(1) access
    TYPES: BEGIN OF ty_dp_state,
             sum   TYPE i,
             paths TYPE STANDARD TABLE OF ty_dp_path WITH EMPTY KEY,
           END OF ty_dp_state.

    DATA tl_dp_states     TYPE HASHED TABLE OF ty_dp_state WITH UNIQUE KEY sum.

    " Initialize with empty path (sum = 0)
    DATA ls_initial_state TYPE ty_dp_state.
    ls_initial_state-sum = 0.
    APPEND VALUE ty_dp_path( sum = 0 ) TO ls_initial_state-paths.
    INSERT ls_initial_state INTO TABLE tl_dp_states.

    " Calculate acceptable range for paths
    DATA(wl_max_tolerance) = CONV wrbtr( wl_target_cents * iv_tolerance_percent * 100 ).
    DATA(wl_min_sum) = CONV wrbtr( wl_target_cents - wl_max_tolerance ).
    DATA(wl_max_sum) = CONV wrbtr( wl_target_cents + wl_max_tolerance ).

    " Process each item
    DATA wl_item_idx    TYPE i VALUE 0.
    DATA lv_total_paths TYPE i VALUE 0.

    LOOP AT it_items INTO xl_item.
      wl_item_idx += 1.
      DATA(wl_amount_cents) = CONV wrbtr( xl_item-amountincompanycodeccy * 100 ).

      " Check timeout
      IF wl_item_idx MOD 5 = 0.  " Check every 5 items
        GET TIME STAMP FIELD wl_current_time.
        wl_elapsed_ms = cl_abap_tstmp=>subtract( tstmp1 = wl_current_time
                                                 tstmp2 = wl_start_time ) * 1000.
        IF wl_elapsed_ms > gc_timeout_ms.
          IF go_out IS BOUND.
            go_out->write( |  TIMEOUT after { wl_elapsed_ms } ms at item { wl_item_idx }| ).
          ENDIF.
          EXIT.
        ENDIF.
      ENDIF.

      " Temporary storage for new states
      DATA tl_new_states TYPE HASHED TABLE OF ty_dp_state WITH UNIQUE KEY sum.

      " For each existing state, try adding current item
      LOOP AT tl_dp_states INTO DATA(ls_state).
        LOOP AT ls_state-paths INTO DATA(ls_path).
          DATA(wl_new_sum) = CONV wrbtr( ls_path-sum + wl_amount_cents ).

          " Only keep paths within reasonable range
          IF wl_new_sum < wl_min_sum OR wl_new_sum > wl_max_sum.
            CONTINUE.
          ENDIF.

          DATA(ls_new_path) = VALUE ty_dp_path( sum        = wl_new_sum
                                                items_used = ls_path-items_used ).
          APPEND wl_item_idx TO ls_new_path-items_used.

          " Add to new states (grouped by sum)
          READ TABLE tl_new_states WITH KEY sum = wl_new_sum
               ASSIGNING FIELD-SYMBOL(<fs_new_state>).

          IF sy-subrc = 0.
            APPEND ls_new_path TO <fs_new_state>-paths.
          ELSE.
            DATA ls_new_state TYPE ty_dp_state.
            ls_new_state-sum = wl_new_sum.
            APPEND ls_new_path TO ls_new_state-paths.
            INSERT ls_new_state INTO TABLE tl_new_states.
          ENDIF.

          lv_total_paths = lv_total_paths + 1.

          " Safety limit to prevent memory explosion
          IF lv_total_paths > iv_max_solutions * 1000.
            IF go_out IS BOUND.
              go_out->write( |  WARNING: Too many paths ({ lv_total_paths }), stopping DP| ).
            ENDIF.
            EXIT.
          ENDIF.
        ENDLOOP.

        IF lv_total_paths > iv_max_solutions * 1000.
          EXIT.
        ENDIF.
      ENDLOOP.

      " Merge new states into main DP table
      LOOP AT tl_new_states INTO ls_new_state.
        READ TABLE tl_dp_states WITH KEY sum = ls_new_state-sum
             ASSIGNING <fs_new_state>.

        IF sy-subrc = 0.
          " Sum already exists - append paths
          APPEND LINES OF ls_new_state-paths TO <fs_new_state>-paths.
        ELSE.
          " New sum - insert state
          INSERT ls_new_state INTO TABLE tl_dp_states.
        ENDIF.
      ENDLOOP.

      IF go_out IS BOUND AND wl_item_idx MOD 10 = 0.
        go_out->write( |  Processed item { wl_item_idx }/{ lv_num_items }, total paths: { lv_total_paths }| ).
      ENDIF.

      IF lv_total_paths > iv_max_solutions * 1000.
        EXIT.
      ENDIF.
    ENDLOOP.

    GET TIME STAMP FIELD wl_current_time.
    wl_elapsed_ms = cl_abap_tstmp=>subtract( tstmp1 = wl_current_time
                                             tstmp2 = wl_start_time ) * 1000.

    IF go_out IS BOUND.
      go_out->write( |  Total DP states: { lines( tl_dp_states ) }| ).
      go_out->write( |  Total paths generated: { lv_total_paths }| ).
      go_out->write( |  Time elapsed: { wl_elapsed_ms } ms| ).
    ENDIF.

    " Extract ONLY solutions that match target EXACTLY
    DATA lv_exact_count TYPE i VALUE 0.

    " Look for sums within exact tolerance
    DATA lv_check_sum   TYPE i.
    lv_check_sum = wl_target_cents - gc_exact_tolerance.

    WHILE lv_check_sum <= wl_target_cents + gc_exact_tolerance.
      READ TABLE tl_dp_states WITH KEY sum = lv_check_sum
           INTO DATA(ls_exact_state).

      IF sy-subrc = 0.
        " Found state(s) with this sum
        LOOP AT ls_exact_state-paths INTO ls_path.
          lv_exact_count = lv_exact_count + 1.

          DATA tl_solution TYPE tty_open_item.
          CLEAR tl_solution.

          " Build solution from item indices
          LOOP AT ls_path-items_used INTO DATA(lv_idx).
            READ TABLE it_items INTO xl_item INDEX lv_idx.
            IF sy-subrc = 0.
              xl_item-selected = abap_true.
              APPEND xl_item TO tl_solution.
            ENDIF.
          ENDLOOP.

          IF tl_solution IS NOT INITIAL.
            " Check if duplicate solution
            lv_is_dup = abap_false.

            LOOP AT tl_all_solutions INTO lt_existing_sol.
              IF iv_are_solutions_equivalent( it_solution1 = tl_solution
                                              it_solution2 = lt_existing_sol ) = abap_true.
                lv_is_dup = abap_true.
                EXIT.
              ENDIF.
            ENDLOOP.

            IF lv_is_dup = abap_false.
              APPEND tl_solution TO tl_all_solutions.
            ENDIF.
          ENDIF.

          IF lines( tl_all_solutions ) >= iv_max_solutions.
            IF go_out IS BOUND.
              go_out->write( |  MAX SOLUTIONS REACHED: { lines( tl_all_solutions ) }| ).
            ENDIF.
            rt_solutions = tl_all_solutions.
            RETURN.
          ENDIF.
        ENDLOOP.
      ENDIF.

      lv_check_sum = lv_check_sum + 1.
    ENDWHILE.

    IF go_out IS BOUND.
      go_out->write( |  Exact matches found: { lv_exact_count }| ).
      go_out->write( |  Unique solutions: { lines( tl_all_solutions ) }| ).
    ENDIF.

    rt_solutions = tl_all_solutions.
  ENDMETHOD.


  METHOD iv_apply_matching_strategy.
    " Apply FIFO, LIFO or None strategy to select best solution

    DATA lt_sorted_solution TYPE tty_open_item.

    CHECK it_solutions IS NOT INITIAL.

    " If only one solution, return it
    IF lines( it_solutions ) = 1.
      rs_selected = it_solutions[ 1 ].
      RETURN.
    ENDIF.

    CASE iv_strategy.
      WHEN 'F'. " FIFO - Select solution with oldest documents
        DATA lv_min_date     TYPE budat VALUE '99991231'.
        " TODO: variable is assigned but never used (ABAP cleaner)
        DATA lv_selected_idx TYPE i.

        LOOP AT it_solutions INTO DATA(lt_solution).
          DATA(lv_idx) = sy-tabix.
          lt_sorted_solution = lt_solution.
          SORT lt_sorted_solution BY postingdate ASCENDING
                                     accountingdocument ASCENDING.

          READ TABLE lt_sorted_solution INTO DATA(ls_item) INDEX 1.
          IF sy-subrc = 0 AND ls_item-postingdate < lv_min_date.
            lv_min_date = ls_item-postingdate.
            lv_selected_idx = lv_idx.
            rs_selected = lt_sorted_solution.
          ENDIF.
        ENDLOOP.

      WHEN 'L'. " LIFO - Select solution with newest documents
        DATA lv_max_date TYPE budat VALUE '00000000'.

        LOOP AT it_solutions INTO lt_solution.
          lv_idx = sy-tabix.
          lt_sorted_solution = lt_solution.
          SORT lt_sorted_solution BY postingdate DESCENDING
                                     accountingdocument DESCENDING.

          READ TABLE lt_sorted_solution INTO ls_item INDEX 1.
          IF sy-subrc = 0 AND ls_item-postingdate > lv_max_date.
            lv_max_date = ls_item-postingdate.
            lv_selected_idx = lv_idx.
            rs_selected = lt_sorted_solution.
          ENDIF.
        ENDLOOP.

      WHEN OTHERS. " No strategy - return first
        rs_selected = it_solutions[ 1 ].

    ENDCASE.
  ENDMETHOD.


  METHOD iv_are_solutions_equivalent.
    " Compare two solutions to see if they use the exact same document line items

    TYPES: BEGIN OF ty_doc_key,
             companycode            TYPE bukrs,
             accountingdocument     TYPE belnr_d,
             fiscalyear             TYPE gjahr,
             accountingdocumentitem TYPE buzei,
           END OF ty_doc_key.

    DATA lt_keys1 TYPE STANDARD TABLE OF ty_doc_key.
    DATA lt_keys2 TYPE STANDARD TABLE OF ty_doc_key.

    " Check if same number of items
    IF lines( it_solution1 ) <> lines( it_solution2 ).
      rv_equivalent = abap_false.
      RETURN.
    ENDIF.

    " Extract full keys from both solutions
    LOOP AT it_solution1 INTO DATA(ls_item1).
      APPEND VALUE #( companycode            = ls_item1-companycode
                      accountingdocument     = ls_item1-accountingdocument
                      fiscalyear             = ls_item1-fiscalyear
                      accountingdocumentitem = ls_item1-accountingdocumentitem )
             TO lt_keys1.
    ENDLOOP.
    SORT lt_keys1 BY companycode
                     accountingdocument
                     fiscalyear
                     accountingdocumentitem.

    LOOP AT it_solution2 INTO DATA(ls_item2).
      APPEND VALUE #( companycode            = ls_item2-companycode
                      accountingdocument     = ls_item2-accountingdocument
                      fiscalyear             = ls_item2-fiscalyear
                      accountingdocumentitem = ls_item2-accountingdocumentitem )
             TO lt_keys2.
    ENDLOOP.
    SORT lt_keys2 BY companycode
                     accountingdocument
                     fiscalyear
                     accountingdocumentitem.

    " Compare sorted keys
    IF lt_keys1 = lt_keys2.
      rv_equivalent = abap_true.
    ELSE.
      rv_equivalent = abap_false.
    ENDIF.
  ENDMETHOD.


  METHOD if_oo_adt_classrun~main.
    DATA lt_customer_requests TYPE tty_customer_batch_request.
    DATA lt_supplier_requests TYPE tty_supplier_batch_request.
    DATA lt_results           TYPE tty_batch_result.
    DATA lt_items             TYPE tty_open_item.
    DATA lv_customer_count    TYPE i.
    DATA lv_supplier_count    TYPE i.

    go_out = out.  " Store reference
    out->write( |TEST 1: Batch Customer Search| ).
    out->write( |{ repeat( val = '-'
                           occ = 60 ) }| ).

    lt_customer_requests = VALUE #(
                                    ( companycode = '1130'
                                    currency    = 'AED'
                                        request_id = iv_safe_uuid( )
                                      customer   = '0001003423'
                                      amount     = '90250.00'
                                      tolerance  = '0.05' )
                                    ( companycode = '1130'
                                    currency    = 'AED'
                                        request_id = iv_safe_uuid( )
                                      customer   = '0001003290'
                                      amount     = '36750.00'
                                      tolerance  = '0.10' )
                                    ( companycode = '1130'
                                    currency    = 'AED'
                                    request_id = iv_safe_uuid( )
                                      customer   = '0001003422'
                                      amount     = '149625'
                                      tolerance  = '1.00' )
                                   ( companycode = '2010'
                                    currency    = 'EUR'
                                    request_id = iv_safe_uuid( )
                                      customer   = '0001000090'
                                      amount     = '2090.80'
                                      tolerance  = '0.00'  )
                                     ( companycode = '1060'
                                    currency    = 'AED'
                                      request_id = iv_safe_uuid( )
                                      customer   = '0000500000'
                                      amount     = '60'
                                      tolerance  = '0.00'  )
                                      ).

    lt_results = ip_search_customer_items_batch( it_requests = lt_customer_requests
                                                 is_config   = VALUE #( item_type         = 'D'
                                                                        months_back       = 6
                                                                        max_items         = 1000
                                                                        matching_strategy = 'N' ) ).

    LOOP AT lt_results INTO DATA(ls_result).
      out->write( |Request ID: { ls_result-request_id }| ).
      out->write( |Customer: { ls_result-partner }  Requested Amount: { ls_result-amount CURRENCY = 'USD' }| ).
      out->write( |Open items found: { ls_result-total_matched }| ).
      out->write( |Documents in match: { lines( ls_result-matched_items ) }| ).
      out->write( |Exact match: { ls_result-exact_match }| ).
      out->write( |Match quality: { ls_result-match_quality }%| ).
      out->write( |Processing time: { ls_result-processing_time } ms| ).

      IF ls_result-matched_items IS NOT INITIAL.
        out->write( |Matched documents:| ).
        DATA lv_total_matched TYPE wrbtr.
        CLEAR lv_total_matched.
        LOOP AT ls_result-matched_items INTO DATA(ls_matched_item).
          out->write(
              |  - Doc { ls_matched_item-accountingdocument } Yr { ls_matched_item-fiscalyear }: { ls_matched_item-amountincompanycodeccy CURRENCY = 'USD' } { ls_matched_item-companycodecurrency }| ).
          lv_total_matched = lv_total_matched + ls_matched_item-amountincompanycodeccy.
        ENDLOOP.
        out->write( |  TOTAL MATCHED: { lv_total_matched CURRENCY = 'USD' }| ).
      ENDIF.
      out->write( | | ).
    ENDLOOP.

    " Test detallado para el primer cliente
    out->write( |DETAILED TEST FOR CUSTOMER 0001003423| ).
    out->write( repeat( val = '='
                        occ = 60 ) ).

    DATA lt_test_items TYPE tty_open_item.
    lt_test_items = ip_search_customer_items( iv_customer    = '0001003423'
                                              iv_companycode = '1130'
                                              iv_currency    = 'AED'
                                              is_config      = VALUE #( months_back = 6 ) ).

    out->write( |Total items found: { lines( lt_test_items ) }| ).
    out->write( |Items details:| ).
    LOOP AT lt_test_items INTO DATA(ls_test_item).
      out->write(
          |  { sy-tabix }: Doc={ ls_test_item-accountingdocument } Amount={ ls_test_item-amountincompanycodeccy }| ).
    ENDLOOP.

    out->write( | | ).
    out->write( |Finding all solutions for 90250.00...| ).

    DATA(lt_all_sols) = iv_find_all_solutions( iv_target            = '90250.00'
                                               it_items             = lt_test_items
                                               iv_tolerance_percent = '0.05'
                                               iv_max_solutions     = 100 ).

    out->write( |Solutions found: { lines( lt_all_sols ) }| ).

    LOOP AT lt_all_sols INTO DATA(lt_one_sol).
      DATA lv_sol_idx TYPE i.
      lv_sol_idx = sy-tabix.
      DATA lv_sum TYPE wrbtr.
      CLEAR lv_sum.
      out->write( |Solution { lv_sol_idx }:| ).
      LOOP AT lt_one_sol INTO DATA(ls_sol_item).
        lv_sum = lv_sum + ls_sol_item-amountincompanycodeccy.
        out->write( |  - Doc { ls_sol_item-accountingdocument }: { ls_sol_item-amountincompanycodeccy }| ).
      ENDLOOP.
      out->write( |  TOTAL: { lv_sum }| ).
    ENDLOOP.

    out->write( |TEST 2: Batch Supplier Search| ).
    out->write( |{ repeat( val = '-'
                           occ = 60 ) }| ).

    lt_supplier_requests = VALUE #( companycode = '1010'
                                    currency    = 'EUR'
                                    ( request_id = iv_safe_uuid( )
                                      supplier   = '0000200001'
                                      amount     = '2500.00'
                                      tolerance  = '0.05' )
                                    ( request_id = iv_safe_uuid( )
                                      supplier   = '0000200002'
                                      amount     = '5000.00'
                                      tolerance  = '0.02' ) ).

    lt_results = ip_search_supplier_items_batch( it_requests = lt_supplier_requests
                                                 is_config   = VALUE #( item_type = 'K'
                                                                        days_back = 15
                                                                        max_items = 1000 ) ).

    LOOP AT lt_results INTO ls_result.
      out->write( |Supplier: { ls_result-partner } Amount: { ls_result-amount }| ).
      out->write( |Items found: { ls_result-total_matched }| ).
      out->write( |Match quality: { ls_result-match_quality }%| ).
      out->write( | | ).
    ENDLOOP.

    out->write( |TEST 3: Universal Batch Search (Customers + Suppliers)| ).
    out->write( |{ repeat( val = '-'
                           occ = 60 ) }| ).

    lt_results = ip_search_universal_batch( it_customer_requests = lt_customer_requests
                                            it_supplier_requests = lt_supplier_requests
                                            is_config            = VALUE #( months_back = 3
                                                                            max_items   = 2000 ) ).

    out->write( |Total results: { lines( lt_results ) }| ).

    CLEAR: lv_customer_count,
           lv_supplier_count.
    LOOP AT lt_results INTO ls_result.
      IF ls_result-partner_type = 'D'.
        lv_customer_count = lv_customer_count + 1.
      ELSEIF ls_result-partner_type = 'K'.
        lv_supplier_count = lv_supplier_count + 1.
      ENDIF.
    ENDLOOP.

    out->write( |Customers: { lv_customer_count }| ).
    out->write( |Suppliers: { lv_supplier_count }| ).
    out->write( | | ).

    out->write( |TEST 4: Single Customer Search (Legacy Method)| ).
    out->write( |{ repeat( val = '-'
                           occ = 60 ) }| ).

    lt_items = ip_search_customer_items( iv_customer    = '0000100001'
                                         iv_companycode = '1010'
                                         iv_currency    = 'EUR'
                                         is_config      = VALUE #( months_back = 6 ) ).

    out->write( |Customer 0000100001 - Items found: { lines( lt_items ) }| ).
    LOOP AT lt_items INTO DATA(ls_item) TO 5.
      out->write(
          |  Doc: { ls_item-accountingdocument } Amount: { ls_item-amountincompanycodeccy } { ls_item-companycodecurrency }| ).
    ENDLOOP.
    out->write( | | ).

    out->write( |TEST 5: GL Account Search| ).
    out->write( |{ repeat( val = '-'
                           occ = 60 ) }| ).

    lt_items = ip_search_gl_items( iv_glaccount   = '0000140000'
                                   iv_companycode = '1010'
                                   iv_currency    = 'EUR'
                                   is_config      = VALUE #( months_back = 6
                                                             max_items   = 500 ) ).

    out->write( |GL Account 0000140000 - Items found: { lines( lt_items ) }| ).
    out->write( | | ).

    out->write( |TEST 6: Best Match Algorithm| ).
    out->write( |{ repeat( val = '-'
                           occ = 60 ) }| ).

    lt_items = ip_search_customer_items( iv_customer    = '0000100001'
                                         iv_companycode = '1010'
                                         is_config      = VALUE #( months_back = 12
                                                                   max_items   = 100 ) ).

    IF lt_items IS NOT INITIAL.
      DATA(ls_match_result) = ip_find_best_match( iv_target_amount     = '5000.00'
                                                  it_available_items   = lt_items
                                                  iv_tolerance_percent = '0.05'
                                                  iv_max_time_ms       = 3000 ).

      out->write( |Target amount: { ls_match_result-bank_amount }| ).
      out->write( |Matched amount: { ls_match_result-matched_amount }| ).
      out->write( |Difference: { ls_match_result-difference }| ).
      out->write( |Match quality: { ls_match_result-match_quality }%| ).
      out->write( |Processing time: { ls_match_result-processing_time } ms| ).
      out->write( |Items in combination: { lines( ls_match_result-matched_items ) }| ).

      LOOP AT ls_match_result-matched_items INTO ls_item.
        out->write( |  - Doc { ls_item-accountingdocument }: { ls_item-amountincompanycodeccy }| ).
      ENDLOOP.
    ELSE.
      out->write( |No items available for matching test| ).
    ENDIF.
  ENDMETHOD.


  METHOD iv_safe_uuid.
    TRY.
        rv_uuid = iv_safe_uuid( ).
      CATCH cx_uuid_error.
        CLEAR rv_uuid.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
