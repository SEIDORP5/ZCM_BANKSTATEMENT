CLASS lhc_zr_febh DEFINITION FINAL INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR febh
      RESULT result.

    METHODS processfiles FOR MODIFY
      IMPORTING keys FOR ACTION febh~processfiles.
ENDCLASS.

CLASS lhc_zr_febh IMPLEMENTATION.
  METHOD get_global_authorizations.
    result-%create = if_abap_behv=>auth-allowed.
    result-%update = if_abap_behv=>auth-allowed.
    result-%delete = if_abap_behv=>auth-allowed.
  ENDMETHOD.

  METHOD processfiles.
    " Acción estática: procesar TODOS los extractos pendientes (inicial o
    " error). Aquí solo se bufferizan las claves; el saver (save_modified)
    " encola el bgPF, que es quien puede hacer COMMIT ENTITIES.
    SELECT sapuuid
      FROM zafebh
      WHERE status = @zcl_bankstatement_types=>ebs_status-initial
         OR status = @zcl_bankstatement_types=>ebs_status-error
      INTO CORRESPONDING FIELDS OF TABLE @zbp_r_febh=>mt_statements_to_process.
  ENDMETHOD.
ENDCLASS.


CLASS lsc_zr_febh DEFINITION INHERITING FROM cl_abap_behavior_saver.
  PROTECTED SECTION.
    METHODS save_modified REDEFINITION.
ENDCLASS.

CLASS lsc_zr_febh IMPLEMENTATION.
  METHOD save_modified.
    " --- ENCOLAR el proceso de fondo con los extractos bufferizados -------
    DATA(tl_keys) = zbp_r_febh=>mt_statements_to_process.
    CLEAR zbp_r_febh=>mt_statements_to_process.

    IF tl_keys IS NOT INITIAL.
      TRY.
          DATA(wl_monitor) = zcl_bgpf_bankstatement=>run_via_bgpf_uncontrolled( tl_keys ).

          " Persistir el monitor: los virtuales bgPFStatus de la UI lo leen
          LOOP AT tl_keys INTO DATA(xl_key).
            UPDATE zafebh
               SET bgpf_monitor = @wl_monitor,
                   bgpf_name    = 'Procesar extractos bancarios'
             WHERE sapuuid = @xl_key-sapuuid.
          ENDLOOP.
        CATCH cx_bgmc INTO DATA(lx_bgmc).
          " Encolado fallido: dejar constancia en los extractos afectados
          DATA(wl_error) = |{ zcl_bankstatement_types=>msg( '032' ) }: { lx_bgmc->get_text( ) }|.
          LOOP AT tl_keys INTO xl_key.
            UPDATE zafebh
               SET status  = @zcl_bankstatement_types=>ebs_status-error,
                   message = @wl_error
             WHERE sapuuid = @xl_key-sapuuid.
          ENDLOOP.
      ENDTRY.
    ENDIF.

    " --- EVENTO de fin: refresca la Object Page al cambiar el estado ------
    RAISE ENTITY EVENT zr_febh~bgPFFinished
          FROM VALUE #( FOR xl_upd IN update-febh
                        WHERE ( %control-status = if_abap_behv=>mk-on )
                        ( CORRESPONDING #( xl_upd ) ) ).
  ENDMETHOD.
ENDCLASS.
