*&---------------------------------------------------------------------*
*& Clase ZCL_BANKSTATEMENT_TYPES - Tipos y constantes compartidos
*&---------------------------------------------------------------------*
*& Contenedor de tipos, constantes y del helper de mensajes (MSAG
*& ZMC_BANKSTATEMENT, generada por ZCL_CM_BANKSTATEMENT_MSAGGEN).
*&---------------------------------------------------------------------*
CLASS zcl_bankstatement_types DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Communication scenario de SALIDA publicado en el tenant (boomerang hacia
    " el servicio inbound SAP_COM_0316). Debe coincidir EXACTAMENTE con el SCO1
    " y con el Communication Arrangement dado de alta por el administrador.
    CONSTANTS c_sapbankstatementapi TYPE if_com_management=>ty_cscn_id VALUE 'ZCS_0316'.

    " Clase de mensajes del motor (única fuente: el generador XCO)
    CONSTANTS c_msag TYPE sy-msgid VALUE 'ZMC_BANKSTATEMENT'.

    " Estados del extracto (dominio ZD_EBS_STATUS)
    CONSTANTS:
      BEGIN OF ebs_status,
        initial      TYPE zr_febh-status VALUE '1',
        posted       TYPE zr_febh-status VALUE '2',
        error        TYPE zr_febh-status VALUE '3',
        no_movements TYPE zr_febh-status VALUE '4',
      END OF ebs_status.

    TYPES ty_msgno TYPE n LENGTH 3.

    TYPES tty_filestring TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    TYPES: BEGIN OF ty_import_file,
             filename   TYPE c LENGTH 100,
             filedate   TYPE datum,
             bankformat TYPE string,
             sender     TYPE string,
             sourcepath TYPE string,
             content    TYPE string,
           END OF ty_import_file,
           tty_import_file TYPE STANDARD TABLE OF ty_import_file.

    TYPES: BEGIN OF ty_file,
             filename   TYPE string,
             filedate   TYPE datum,
             bankformat TYPE string,
             sender     TYPE string,
             sourcepath TYPE string,
             t_content  TYPE tty_filestring,
           END OF ty_file,
           tty_file TYPE STANDARD TABLE OF ty_file.

    TYPES: BEGIN OF ty_soapmessageresponse,
             messagetype        TYPE bapi_msg,
             messagecontexttype TYPE n LENGTH 1,
             message            TYPE string,
           END OF ty_soapmessageresponse,
           tty_soapmessageresponse TYPE TABLE OF ty_soapmessageresponse WITH EMPTY KEY.

    TYPES: BEGIN OF ty_keys,
             sapuuid TYPE zr_febh-sapuuid,
           END OF ty_keys.

    TYPES tt_keys TYPE TABLE OF ty_keys.

    " Tipos elemento + rango (los RANGE OF no compilan directamente en firmas)
    TYPES ty_filename TYPE zr_febh-filename.
    TYPES tr_filename TYPE RANGE OF ty_filename.
    TYPES ty_filedate TYPE zr_febh-filecreationdate.
    TYPES tr_filedate TYPE RANGE OF ty_filedate.
    TYPES ty_status   TYPE zr_febh-status.
    TYPES tr_status   TYPE RANGE OF ty_status.
    TYPES ty_sapuuid  TYPE zr_febh-sapuuid.
    TYPES tr_sapuuid  TYPE RANGE OF ty_sapuuid.

    TYPES tt_currency TYPE TABLE OF i_currency WITH EMPTY KEY.
    TYPES tt_housebankaccountlinkage TYPE TABLE OF i_housebankaccountlinkage WITH EMPTY KEY.

    TYPES tty_febep TYPE TABLE OF zr_febp WITH EMPTY KEY.
    TYPES ty_febep  TYPE zr_febp.

    TYPES: BEGIN OF ty_ebs_parse.
             INCLUDE TYPE  zr_febh AS febh.
    TYPES:   febep TYPE tty_febep,
           END OF ty_ebs_parse,
           tty_ebs_parse TYPE STANDARD TABLE OF ty_ebs_parse WITH EMPTY KEY.

    TYPES ty_numc6   TYPE n LENGTH 6.
    TYPES tty_febh   TYPE TABLE OF zafebh.
    TYPES tty_febp   TYPE TABLE OF zafebp.
    TYPES ty_char1   TYPE c LENGTH 1.
    TYPES tty_string TYPE TABLE OF string WITH EMPTY KEY.

    "! <p class="shorttext synchronized" lang="es">Texto de mensaje de la MSAG del motor</p>
    "! Resuelve un mensaje de <em>ZMC_BANKSTATEMENT</em> en forma dinámica
    "! (no exige que el mensaje exista en compilación; desacoplado del F9
    "! del generador).
    CLASS-METHODS msg
      IMPORTING iv_number      TYPE ty_msgno
                iv_v1          TYPE simple OPTIONAL
                iv_v2          TYPE simple OPTIONAL
                iv_v3          TYPE simple OPTIONAL
                iv_v4          TYPE simple OPTIONAL
      RETURNING VALUE(rv_text) TYPE string.

ENDCLASS.



CLASS ZCL_BANKSTATEMENT_TYPES IMPLEMENTATION.


  METHOD msg.
    " ID vía variable: forma 100% dinámica, sin validación en compilación
    DATA(lv_msgid) = c_msag.
    MESSAGE ID lv_msgid TYPE 'S' NUMBER iv_number
            WITH iv_v1 iv_v2 iv_v3 iv_v4
            INTO rv_text.
  ENDMETHOD.
ENDCLASS.
