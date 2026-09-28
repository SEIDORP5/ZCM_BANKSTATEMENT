@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Extracto electronico (Posiciones)'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #S,
    dataClass: #MIXED
}
define view entity ZR_FEBP
  as select from zafebp
  association to parent ZR_FEBH as _FEBH on $projection.SapParentUuid = _FEBH.Sapuuid
{
  key sap_uuid                      as SapUuid,
      sap_parent_uuid               as SapParentUuid,
      bankpostingdate               as Bankpostingdate,
      bankvaluedate                 as Bankvaluedate,
      amountinbankaccountcurrency   as Amountinbankaccountcurrency,
      feeamountintransactioncrcy    as Feeamountintransactioncrcy,
      paymenttransactioncode        as Paymenttransactioncode,
      debitcreditcode               as Debitcreditcode,
      ebscheck                      as Ebscheck,
      businesspartner               as BusinessPartner,
      bankstatementitemdescription1 as Bankstatementitemdescription1,
      bankstatementitemdescription2 as Bankstatementitemdescription2,
      notetopayeeinbankstatement    as Notetopayeeinbankstatement,
      iditem                        as Iditem,
      iddescriptionitem             as Iddescriptionitem,
      fileitemdata                  as Fileitemdata,
      @Semantics.user.createdBy: true
      created_by                 as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at                 as CreatedAt,
      @Semantics.user.lastChangedBy: true
      last_changed_by            as LastChangedBy,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      last_changed_at            as LastChangedAt,
      _FEBH
}
