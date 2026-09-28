*&---------------------------------------------------------------------*
*& Clase ZCL_CSB43_CONSTANTS - Posiciones de campo del formato CSB43
*&---------------------------------------------------------------------*
*& Contiene todos los offsets y longitudes de campo de la norma 43 (AEB).
*& Elimina los números mágicos del código de análisis.
*&---------------------------------------------------------------------*
CLASS zcl_csb43_constants DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    " Tipos de registro
    CONSTANTS:
      c_record_type_header TYPE c LENGTH 2 VALUE '11',
      c_record_type_item   TYPE c LENGTH 2 VALUE '22',
      c_record_type_detail TYPE c LENGTH 2 VALUE '23',
      c_record_type_footer TYPE c LENGTH 2 VALUE '33'.

    " Registro 11 - Cabecera
    CONSTANTS:
      c_h_bank_code_offset    TYPE i VALUE 2,
      c_h_bank_code_length    TYPE i VALUE 8,
      c_h_account_offset      TYPE i VALUE 10,
      c_h_account_length      TYPE i VALUE 10,
      c_h_start_date_offset   TYPE i VALUE 20,
      c_h_start_date_length   TYPE i VALUE 6,
      c_h_end_date_offset     TYPE i VALUE 26,
      c_h_end_date_length     TYPE i VALUE 6,
      c_h_debit_credit_offset TYPE i VALUE 32,
      c_h_amount_offset       TYPE i VALUE 33,
      c_h_amount_length       TYPE i VALUE 14,
      c_h_currency_offset     TYPE i VALUE 47,
      c_h_currency_length     TYPE i VALUE 3.

    " Registro 22 - Movimiento
    CONSTANTS:
      c_i_posting_date_offset  TYPE i VALUE 10,
      c_i_posting_date_length  TYPE i VALUE 6,
      c_i_value_date_offset    TYPE i VALUE 16,
      c_i_value_date_length    TYPE i VALUE 6,
      c_i_trans_code_offset    TYPE i VALUE 22,
      c_i_trans_code_length    TYPE i VALUE 2,
      c_i_trans_subcode_offset TYPE i VALUE 24,
      c_i_trans_subcode_length TYPE i VALUE 3,
      c_i_debit_credit_offset  TYPE i VALUE 27,
      c_i_amount_offset        TYPE i VALUE 28,
      c_i_amount_length        TYPE i VALUE 14,
      c_i_doc_num_offset       TYPE i VALUE 42,
      c_i_doc_num_length       TYPE i VALUE 10,
      c_i_ref1_offset          TYPE i VALUE 52,
      c_i_ref1_length          TYPE i VALUE 12,
      c_i_ref2_offset          TYPE i VALUE 64,
      c_i_ref2_length          TYPE i VALUE 16.

    " Registro 23 - Detalle adicional
    CONSTANTS:
      c_d_description_offset TYPE i VALUE 4,
      c_d_max_line_length    TYPE i VALUE 65.

    " Registro 33 - Totales
    CONSTANTS:
      c_f_credit_amount_offset   TYPE i VALUE 25,
      c_f_credit_amount_length   TYPE i VALUE 14,
      c_f_debit_amount_offset    TYPE i VALUE 44,
      c_f_debit_amount_length    TYPE i VALUE 14,
      c_f_closing_balance_ind    TYPE i VALUE 58,
      c_f_closing_balance_offset TYPE i VALUE 59,
      c_f_closing_balance_length TYPE i VALUE 14.

    " Indicadores Debe/Haber
    CONSTANTS:
      c_debit_indicator  TYPE c LENGTH 1 VALUE '1',
      c_credit_indicator TYPE c LENGTH 2 VALUE '2',
      c_debit_code       TYPE c LENGTH 1 VALUE 'S',
      c_credit_code      TYPE c LENGTH 1 VALUE 'H'.

protected section.
private section.
ENDCLASS.



CLASS ZCL_CSB43_CONSTANTS IMPLEMENTATION.
ENDCLASS.
