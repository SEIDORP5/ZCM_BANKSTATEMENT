*&---------------------------------------------------------------------*
*& Clase ZCL_BANKSTATEMENT_DUP_CHECK - Detección de ficheros duplicados
*&---------------------------------------------------------------------*
*& Comprueba contra el monitor (ZR_FEBH) si un fichero ya fue procesado.
*& Criterio actual: nombre de fichero.
*&---------------------------------------------------------------------*
CLASS zcl_bankstatement_dup_check DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ty_duplicate_check_result,
             is_duplicate    TYPE abap_boolean,
             existing_uuid   TYPE sysuuid_x16,
             existing_status TYPE zr_febh-status,
             message         TYPE string,
           END OF ty_duplicate_check_result,
           tt_duplicate_check_result TYPE STANDARD TABLE OF ty_duplicate_check_result WITH EMPTY KEY.

    "! <p class="shorttext synchronized" lang="es">Comprueba si un fichero ya existe</p>
    METHODS ip_check_file_exists
      IMPORTING
        iv_filename      TYPE zr_febh-filename
        iv_filedate      TYPE datum OPTIONAL
      RETURNING
        VALUE(rs_result) TYPE ty_duplicate_check_result.

    "! <p class="shorttext synchronized" lang="es">Comprueba un lote de ficheros</p>
    "! Devuelve una fila por fichero de entrada, en el mismo orden.
    METHODS ip_check_batch_exists
      IMPORTING
        it_filenames      TYPE zcl_bankstatement_types=>tty_import_file
      RETURNING
        VALUE(rt_results) TYPE tt_duplicate_check_result.

ENDCLASS.



CLASS ZCL_BANKSTATEMENT_DUP_CHECK IMPLEMENTATION.


  METHOD ip_check_file_exists.
    CLEAR rs_result.

    SELECT SINGLE sapuuid, status, message
      FROM zr_febh
      WITH PRIVILEGED ACCESS
      WHERE filename = @iv_filename
      INTO (@rs_result-existing_uuid, @rs_result-existing_status, @rs_result-message).

    IF sy-subrc = 0.
      rs_result-is_duplicate = abap_true.
      rs_result-message = zcl_bankstatement_types=>msg( iv_number = '006'
                                                        iv_v1     = iv_filename
                                                        iv_v2     = rs_result-existing_status ).
    ELSE.
      rs_result-is_duplicate = abap_false.
    ENDIF.

  ENDMETHOD.


  METHOD ip_check_batch_exists.
    DATA tl_filenames TYPE STANDARD TABLE OF zr_febh-filename.

    tl_filenames = VALUE #( FOR wl_file IN it_filenames ( wl_file-filename ) ).

    " Guard obligatorio: un FOR ALL ENTRIES con tabla vacía leería TODO el monitor
    IF tl_filenames IS NOT INITIAL.
      SELECT filename, sapuuid, status, message
        FROM zr_febh
        WITH PRIVILEGED ACCESS
        FOR ALL ENTRIES IN @tl_filenames
        WHERE filename = @tl_filenames-table_line
        INTO TABLE @DATA(tl_existing).
    ENDIF.

    LOOP AT it_filenames INTO DATA(xl_file).
      DATA(xl_result) = VALUE ty_duplicate_check_result( ).

      READ TABLE tl_existing INTO DATA(xl_existing)
        WITH KEY filename = xl_file-filename.

      IF sy-subrc = 0.
        xl_result-is_duplicate    = abap_true.
        xl_result-existing_uuid   = xl_existing-sapuuid.
        xl_result-existing_status = xl_existing-status.
        xl_result-message = zcl_bankstatement_types=>msg( iv_number = '006'
                                                          iv_v1     = xl_file-filename
                                                          iv_v2     = xl_existing-status ).
      ELSE.
        xl_result-is_duplicate = abap_false.
      ENDIF.

      APPEND xl_result TO rt_results.
    ENDLOOP.

  ENDMETHOD.
ENDCLASS.
