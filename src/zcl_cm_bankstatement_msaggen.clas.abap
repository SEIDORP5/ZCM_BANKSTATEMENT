"! <p class="shorttext synchronized" lang="es">Genera la MSAG ZMC_BANKSTATEMENT</p>
"! Ejecutar con <strong>F9</strong> desde Eclipse/ADT. Idempotente: el PUT
"! reemplaza la clase de mensajes ENTERA, por lo que este generador es la
"! <strong>única fuente de verdad</strong> de TODOS los mensajes del motor.
"! Nunca crear un segundo generador de la misma MSAG.
CLASS zcl_cm_bankstatement_msaggen DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

  PRIVATE SECTION.
    CONSTANTS co_package   TYPE sxco_package   VALUE 'ZCM_BANKSTATEMENT'.
    CONSTANTS co_transport TYPE sxco_transport VALUE 'A16K900290'.
ENDCLASS.



CLASS ZCL_CM_BANKSTATEMENT_MSAGGEN IMPLEMENTATION.


  METHOD if_oo_adt_classrun~main.
    TRY.
        DATA(lo_env) = xco_cp_generation=>environment->dev_system( co_transport ).
        DATA(lo_put) = lo_env->for-msag->create_put_operation( ).

        DATA(lo_spec) = lo_put->add_object( 'ZMC_BANKSTATEMENT'
          )->set_package( co_package
          )->create_form_specification( ).

        lo_spec->set_short_description( 'Mensajes del motor de extractos bancarios' ).

        " ---- Proceso de ficheros -------------------------------------------
        lo_spec->add_message( '001' )->set_short_text( 'Iniciando proceso de &1 fichero(s)' ).
        lo_spec->add_message( '002' )->set_short_text( 'Fichero &1: &2' ).
        lo_spec->add_message( '003' )->set_short_text( 'Formato de fichero no válido: separadores no reconocidos' ).
        lo_spec->add_message( '004' )->set_short_text( 'Fichero vacío tras la decodificación' ).
        lo_spec->add_message( '005' )->set_short_text( 'Fichero &1 analizado correctamente' ).
        lo_spec->add_message( '006' )->set_short_text( 'El fichero &1 ya se procesó anteriormente (estado &2)' ).
        lo_spec->add_message( '007' )->set_short_text( '&1 extracto(s) analizado(s) correctamente' ).
        lo_spec->add_message( '008' )->set_short_text( 'No hay ficheros que procesar tras el control de duplicados' ).

        " ---- Persistencia en el monitor ------------------------------------
        lo_spec->add_message( '009' )->set_short_text( 'Error al registrar los extractos en el monitor' ).
        lo_spec->add_message( '010' )->set_short_text( 'Extractos registrados correctamente en el monitor EBS' ).
        lo_spec->add_message( '011' )->set_short_text( '&1 extracto(s) guardado(s) en el monitor' ).

        " ---- Envío al servicio de contabilización --------------------------
        lo_spec->add_message( '012' )->set_short_text( 'Extracto sin movimientos' ).
        lo_spec->add_message( '013' )->set_short_text( 'Extracto contabilizado con el número &1' ).
        lo_spec->add_message( '014' )->set_short_text( 'Error al contabilizar el extracto' ).
        lo_spec->add_message( '015' )->set_short_text( 'Error de comunicación SOAP' ).
        lo_spec->add_message( '016' )->set_short_text( 'Error de sistema en el envío' ).
        lo_spec->add_message( '017' )->set_short_text( 'Envío finalizado: &1 correctos, &2 con error, &3 sin movimientos' ).

        " ---- Conexión ------------------------------------------------------
        lo_spec->add_message( '018' )->set_short_text( 'No se ha encontrado el Communication Arrangement &1' ).
        lo_spec->add_message( '019' )->set_short_text( 'Conexión con el servicio de extractos establecida' ).
        lo_spec->add_message( '020' )->set_short_text( 'Error al preparar la conexión con el servicio' ).

        " ---- Actualización de estados --------------------------------------
        lo_spec->add_message( '021' )->set_short_text( 'Extracto &1 no encontrado en el monitor' ).
        lo_spec->add_message( '022' )->set_short_text( 'Error al actualizar el estado del extracto &1' ).
        lo_spec->add_message( '023' )->set_short_text( 'Error al confirmar los cambios del extracto &1' ).

        " ---- Proceso desde el monitor (APJ / botón Procesar) ---------------
        lo_spec->add_message( '024' )->set_short_text( 'Buscando extractos pendientes en el monitor' ).
        lo_spec->add_message( '025' )->set_short_text( 'Procesando &1 extracto(s) seleccionado(s)' ).
        lo_spec->add_message( '026' )->set_short_text( 'No se han encontrado extractos pendientes de procesar' ).
        lo_spec->add_message( '027' )->set_short_text( '&1 extracto(s) encontrado(s) en el monitor' ).
        lo_spec->add_message( '028' )->set_short_text( 'Proceso finalizado: &1 extracto(s) enviado(s)' ).

        " ---- Errores técnicos ----------------------------------------------
        lo_spec->add_message( '029' )->set_short_text( 'Error técnico durante el proceso' ).
        lo_spec->add_message( '030' )->set_short_text( 'Error de análisis del fichero CSB43' ).
        lo_spec->add_message( '033' )->set_short_text( 'Error al confirmar los cambios en la base de datos' ).

        " ---- Proceso de fondo (bgPF) ---------------------------------------
        lo_spec->add_message( '031' )->set_short_text( 'Proceso de fondo encolado (&1 extracto(s))' ).
        lo_spec->add_message( '032' )->set_short_text( 'Error al encolar el proceso de fondo' ).

        lo_put->execute( ).

        out->write( |OK - MSAG ZMC_BANKSTATEMENT generada en { co_package } vía TR { co_transport }| ).
      CATCH cx_root INTO DATA(lx).
        out->write( |Error: { lx->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
