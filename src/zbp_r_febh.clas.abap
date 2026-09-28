CLASS zbp_r_febh DEFINITION PUBLIC ABSTRACT FINAL FOR BEHAVIOR OF zr_febh.
  PUBLIC SECTION.
    " Buffer de la acción processfiles: el handler lo rellena y el saver
    " (save_modified) lo consume para encolar el proceso de fondo bgPF
    CLASS-DATA mt_statements_to_process TYPE zcl_bankstatement_types=>tt_keys.
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZBP_R_FEBH IMPLEMENTATION.
ENDCLASS.
