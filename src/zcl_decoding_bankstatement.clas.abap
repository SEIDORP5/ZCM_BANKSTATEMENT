CLASS zcl_decoding_bankstatement DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS base64_to_utf8
      IMPORTING i_content_base64      TYPE string
      RETURNING VALUE(r_content_utf8) TYPE string.

    CLASS-METHODS base64_to_hexadecimal
      IMPORTING i_content_base64             TYPE string
      RETURNING VALUE(r_content_hexadecimal) TYPE xstring.

    CLASS-METHODS hexadecimal_to_utf8
      IMPORTING i_content_hexadecimal TYPE xstring
      RETURNING VALUE(r_content_utf8) TYPE string.

    CLASS-METHODS hexadecimal_to_base64
      IMPORTING i_content_hexadecimal   TYPE xstring
      RETURNING VALUE(r_content_base64) TYPE string.
ENDCLASS.



CLASS ZCL_DECODING_BANKSTATEMENT IMPLEMENTATION.


  METHOD base64_to_utf8.
    DATA(wl_xstring) = base64_to_hexadecimal( i_content_base64 = i_content_base64 ).
    r_content_utf8 = hexadecimal_to_utf8( i_content_hexadecimal = wl_xstring ).
  ENDMETHOD.


  METHOD base64_to_hexadecimal.
    DATA(wl_content_base64) = i_content_base64.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>cr_lf IN wl_content_base64 WITH ''.
    REPLACE ALL OCCURRENCES OF cl_abap_char_utilities=>newline IN wl_content_base64 WITH ''.
    r_content_hexadecimal = xco_cp=>string( wl_content_base64
      )->as_xstring( xco_cp_binary=>text_encoding->base64
      )->value.
  ENDMETHOD.


  METHOD hexadecimal_to_utf8.
    r_content_utf8 = xco_cp=>xstring( i_content_hexadecimal
     )->as_string( xco_cp_character=>code_page->utf_8
     )->value.
  ENDMETHOD.


  METHOD hexadecimal_to_base64.
    r_content_base64 = xco_cp=>xstring( i_content_hexadecimal
     )->as_string( xco_cp_binary=>text_encoding->base64
     )->value.
  ENDMETHOD.
ENDCLASS.
