"! APJ + APLO Generator for Bank Statement
"! Creates:
"!   - APLO ZAL_BANKSTATEMENT + subobj ZALS_BANKSTATEMENT (cl_bali_object_handler)
"!   - SAJC ZJC_BANKSTATEMENT (Catalog Entry, class_based)
"!   - SAJT ZJT_BANKSTATEMENT_GET (Template seeded with exec class defaults)
"! Run with F9 from Eclipse/ADT. Idempotent (skips already-existing).
CLASS zcl_cm_bankstatement_apj_gen DEFINITION
  PUBLIC FINAL CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

protected section.
  PRIVATE SECTION.
    CONSTANTS co_package      TYPE c LENGTH 30 VALUE 'ZCM_BANKSTATEMENT'.
    CONSTANTS co_transport    TYPE c LENGTH 20 VALUE 'A16K900152'.
    CONSTANTS co_exec_class   TYPE c LENGTH 30 VALUE 'ZCL_APJ_BANKSTATEMENT'.
    CONSTANTS co_catalog_name TYPE c LENGTH 40 VALUE 'ZJC_BANKSTATEMENT'.
    " Nombre real del template en el sistema (antes 'ZJT_BANKSTATEMENT_GET', desincronizado)
    CONSTANTS co_template_nm  TYPE c LENGTH 40 VALUE 'ZJT_BANKSTATEMENT'.
    CONSTANTS co_aplo_object  TYPE c LENGTH 20 VALUE 'ZAL_BANKSTATEMENT'.
    CONSTANTS co_aplo_subobj  TYPE c LENGTH 20 VALUE 'ZALS_BANKSTATEMENT'.

    METHODS create_aplo IMPORTING io_out TYPE REF TO if_oo_adt_classrun_out.
    METHODS create_apj  IMPORTING io_out TYPE REF TO if_oo_adt_classrun_out.
ENDCLASS.



CLASS ZCL_CM_BANKSTATEMENT_APJ_GEN IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.
    create_aplo( out ).
    create_apj( out ).
  ENDMETHOD.


  METHOD create_aplo.
    DATA(lo_handler) = cl_bali_object_handler=>get_instance( ).

    " Idempotent check via read_object (raises if not exists)
    DATA lv_exists TYPE abap_bool VALUE abap_false.
    TRY.
        lo_handler->read_object(
          EXPORTING iv_object       = CONV #( co_aplo_object )
          IMPORTING ev_object_text  = DATA(lv_text)
                    et_subobjects   = DATA(lt_subs) ).
        lv_exists = abap_true.
      CATCH cx_bali_objects.
        lv_exists = abap_false.
    ENDTRY.

    IF lv_exists = abap_true.
      io_out->write( |APLO { co_aplo_object } already exists| ).
      RETURN.
    ENDIF.

    " Create APLO + subobject in one call
    TRY.
        DATA lt_subobjects TYPE if_bali_object_handler=>ty_tab_subobject.
        APPEND VALUE #( subobject      = co_aplo_subobj
                        subobject_text = 'Bank Statement Process' )
               TO lt_subobjects.

        lo_handler->create_object(
          EXPORTING iv_object            = CONV #( co_aplo_object )
                    iv_object_text       = 'Bank Statement Application Log'
                    it_subobjects        = lt_subobjects
                    iv_package           = CONV #( co_package )
                    iv_transport_request = CONV #( co_transport ) ).
        io_out->write( |APLO { co_aplo_object } + subobj { co_aplo_subobj } created| ).
      CATCH cx_bali_objects INTO DATA(lx_bali).
        io_out->write( |APLO error: { lx_bali->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.


  METHOD create_apj.
    DATA(lo_dt) = cl_apj_dt_create_content=>get_instance( ).

    TRY.
        IF lo_dt->exists_job_cat_entry( iv_catalog_name = co_catalog_name ) = abap_false.
          lo_dt->create_job_cat_entry(
            iv_catalog_name       = co_catalog_name
            iv_class_name         = co_exec_class
            iv_text               = 'Extracto electrónico: Procesado'
            iv_catalog_entry_type = cl_apj_dt_create_content=>class_based
            iv_transport_request  = co_transport
            iv_package            = co_package ).
          io_out->write( |SAJC { co_catalog_name } created| ).
        ELSE.
          io_out->write( |SAJC { co_catalog_name } already exists| ).
        ENDIF.

        DATA lt_params TYPE if_apj_dt_exec_object=>tt_templ_val.
        NEW zcl_apj_bankstatement( )->if_apj_dt_exec_object~get_parameters(
          IMPORTING et_parameter_val = lt_params ).

        IF lo_dt->exists_job_template_entry( iv_template_name = co_template_nm ) = abap_false.
          lo_dt->create_job_template_entry(
            iv_template_name     = co_template_nm
            iv_catalog_name      = co_catalog_name
            iv_text              = 'Extracto electrónico: Procesado'
            it_parameters        = lt_params
            iv_transport_request = co_transport
            iv_package           = co_package ).
          io_out->write( |SAJT { co_template_nm } created with defaults| ).
        ELSE.
          io_out->write( |SAJT { co_template_nm } already exists| ).
        ENDIF.

      CATCH cx_root INTO DATA(lx).
        io_out->write( |APJ error: { lx->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
