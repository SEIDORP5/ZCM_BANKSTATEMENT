@EndUserText.label: 'Log de proceso del extracto'
@ObjectModel.query.implementedBy: 'ABAP:ZCL_FEBH_LOG_QUERY'
define custom entity ZC_FEBH_LOG
{
      // UUID del extracto (external_id del BALI: referencia única)
  key FebhUUID            : sysuuid_x16;

      @UI.lineItem: [ { position: 5 } ]
      @EndUserText.label: 'Nº'
  key Sequence            : abap.int4;

      @UI.lineItem: [ { position: 10, criticality: 'SeverityCriticality', criticalityRepresentation: #WITH_ICON } ]
      @EndUserText.label: 'Severidad'
      Severity            : abap.char(1);

      @UI.hidden: true
      SeverityCriticality : abap.int4;

      @UI.lineItem: [ { position: 20 } ]
      @EndUserText.label: 'Mensaje'
      Message             : abap.char(250);
}
