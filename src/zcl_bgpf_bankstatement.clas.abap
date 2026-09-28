*&---------------------------------------------------------------------*
*& Clase ZCL_BGPF_BANKSTATEMENT - Proceso de fondo de envío de extractos
*&---------------------------------------------------------------------*
*& Operación bgPF (tx uncontrolled) encolada desde el saver del BO
*& ZR_FEBH (acción processfiles). Envía los extractos indicados a la
*& API de contabilización. El orquestador re-lee de BD filtrando por
*& estado pendiente (guard de idempotencia) y cada actualización de
*& estado hace COMMIT y dispara el evento bgPFFinished vía saver.
*&---------------------------------------------------------------------*
CLASS zcl_bgpf_bankstatement DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_bgmc_op_single_tx_uncontr.

    METHODS constructor
      IMPORTING it_keys TYPE zcl_bankstatement_types=>tt_keys.

    "! <p class="shorttext synchronized" lang="es">Encola el envío de extractos en bgPF</p>
    "! Devuelve el string del monitor de proceso para persistirlo en la
    "! cabecera (los virtuales bgPFStatus lo leen para pintar el estado).
    CLASS-METHODS run_via_bgpf_uncontrolled
      IMPORTING it_keys           TYPE zcl_bankstatement_types=>tt_keys
      RETURNING VALUE(rv_monitor) TYPE string
      RAISING   cx_bgmc.

  PRIVATE SECTION.
    DATA mt_keys TYPE zcl_bankstatement_types=>tt_keys.
ENDCLASS.



CLASS ZCL_BGPF_BANKSTATEMENT IMPLEMENTATION.


  METHOD constructor.
    mt_keys = it_keys.
  ENDMETHOD.


  METHOD if_bgmc_op_single_tx_uncontr~execute.
    " El orquestador aplica el guard de idempotencia (solo pendientes),
    " postea, actualiza estados con COMMIT por extracto y persiste el
    " log BALI de cada uno
    DATA(lo_orchestrator) = NEW zcl_bankstatement_orchestrator( ).

    lo_orchestrator->ip_process_files_from_database( it_keys     = mt_keys
                                                     iv_job_mode = abap_true ).
  ENDMETHOD.


  METHOD run_via_bgpf_uncontrolled.
    IF it_keys IS INITIAL.
      RETURN.
    ENDIF.

    DATA(lo_monitor) = cl_bgmc_process_factory=>get_default( )->create(
                           )->set_name( |Procesar extractos bancarios|
                           )->set_operation_tx_uncontrolled(
                               NEW zcl_bgpf_bankstatement( it_keys )
                           )->save_for_execution( ).

    rv_monitor = lo_monitor->to_string( ).
  ENDMETHOD.
ENDCLASS.
