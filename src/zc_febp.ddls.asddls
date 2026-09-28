@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Extracto electronico (Posiciones)'
@Metadata.ignorePropagatedAnnotations: true
@Metadata.allowExtensions: true

define view entity ZC_FEBP
  as projection on ZR_FEBP
{
  key SapUuid,
      SapParentUuid,
      Bankpostingdate,
      Bankvaluedate,

      // Moneda del extracto (cabecera) para formatear los importes
      _FEBH.Currency as Currency,

      Amountinbankaccountcurrency,
      Feeamountintransactioncrcy,

      Paymenttransactioncode,
      Debitcreditcode,
      Ebscheck,
      BusinessPartner,
      Bankstatementitemdescription1,
      Bankstatementitemdescription2,
      Notetopayeeinbankstatement,
      Iditem,
      Iddescriptionitem,
      Fileitemdata,
      CreatedBy,
      CreatedAt,
      LastChangedBy,
      LastChangedAt,
      /* Associations */
      _FEBH : redirected to parent Zc_Febh
}
