@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Extracto electronico (Cabecera)'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #S,
    dataClass: #MIXED
}
define root view entity ZR_FEBH
  as select from zafebh
  association to ZR_EBS_STATUS_VH as _ebsstatus on  $projection.status  = _ebsstatus.Value
                                                and _ebsstatus.Language = $session.system_language
  composition [0..*] of ZR_FEBP   as _FEBP
{
  key sapuuid                                                as Sapuuid,
      externalid                                             as Externalid,
      bankstatement                                          as Bankstatement,
      filename                                               as Filename,
      bankcountry                                            as Bankcountry,
      banknumber                                             as Banknumber,
      bankaccount                                            as Bankaccount,
      iban                                                   as Iban,
      swift                                                  as Swift,
      fileheaddata                                           as Fileheaddata,
      ebsformat                                              as Ebsformat,
      periodstartdate                                        as Periodstartdate,
      periodenddate                                          as Periodenddate,
      currency                                               as Currency,
      openingbalamtinbankacctc                               as Openingbalamtinbankacctc,
      cast ( openingbalamtinbankacctc as abap.dec( 15, 2 ) ) as OpeningbalamtinbankacctcCalc,
      clsgbalamtinbkacctcrcy                                 as Clsgbalamtinbkacctcrcy,
      cast ( clsgbalamtinbkacctcrcy as abap.dec( 15, 2 ) )   as clsgbalamtinbkacctcrcyCalc,
      totaldebitamtinbkacctcrc                               as Totaldebitamtinbkacctcrc,
      cast ( totaldebitamtinbkacctcrc as abap.dec( 15, 2 ) ) as TotaldebitamtinbkacctcrcCalc,
      totalcreditamtinbkacctcr                               as Totalcreditamtinbkacctcr,
      cast ( totalcreditamtinbkacctcr as abap.dec( 15, 2 ) ) as TotalcreditamtinbkacctcrCalc,
      bankstatementnumberofitems                             as Bankstatementnumberofitems,
      filecreationdate                                       as Filecreationdate,
      calculatedpostingdate                                  as CalculationDate,
      status                                                 as status,
      case status
       when  '1'  then 5
       when '2' then 3
       when  '3'  then 1
       when '4' then  2
       else
          5
       end                                                   as CriticalityStatus,
      _ebsstatus.Description                                 as StatusDescription,
      ''                                                     as EBSTrigger,
      bgpf_name                                              as bgPFName,
      bgpf_monitor                                           as bgPFMonitor,
      message                                                as message,
      @Semantics.user.createdBy: true
      created_by                                             as CreatedBy,
      @Semantics.systemDateTime.createdAt: true
      created_at                                             as CreatedAt,
      @Semantics.user.lastChangedBy: true
      last_changed_by                                        as LastChangedBy,
      @Semantics.systemDateTime.localInstanceLastChangedAt: true
      last_changed_at                                        as LastChangedAt,
      _FEBP
}
