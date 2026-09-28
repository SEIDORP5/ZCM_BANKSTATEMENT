@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Bank Statement (Header)'
@Metadata.ignorePropagatedAnnotations: true
@Metadata.allowExtensions: true

define root view entity Zc_Febh
  provider contract transactional_query
  as projection on ZR_FEBH

  association [0..*] to ZC_FEBH_LOG as _Log
    on $projection.Sapuuid = _Log.FebhUUID

{
  key     Sapuuid,
          Externalid,
          Bankstatement,
          Filename,
          Bankcountry,
          Banknumber,
          Bankaccount,
          Iban,
          Swift,
          Fileheaddata,
          Ebsformat,
          Periodstartdate,
          Periodenddate,
          Currency,

          @Semantics.amount.currencyCode: 'Currency'
          OpeningbalamtinbankacctcCalc,
          @Semantics.amount.currencyCode: 'Currency'
          clsgbalamtinbkacctcrcyCalc,
          @Semantics.amount.currencyCode: 'Currency'
          TotaldebitamtinbkacctcrcCalc,
          @Semantics.amount.currencyCode: 'Currency'
          TotalcreditamtinbkacctcrCalc,

          Bankstatementnumberofitems,
          Filecreationdate,
          CalculationDate,

          @Consumption.valueHelpDefinition:
          [{ entity: { name : 'ZR_EBS_STATUS_VH' , element: 'Value' } }]
          @ObjectModel.text.element: [ 'StatusDescription' ]
          status,
          StatusDescription,
          CriticalityStatus,
          @ObjectModel.text.element: [ 'bgpfstatusdescription' ]
          @ObjectModel.virtualElementCalculatedBy: 'ABAP:ZCL_VE_GEN_BGPF'
  virtual BGPFStatus            : ze_bgpf_status,
          @ObjectModel.virtualElementCalculatedBy: 'ABAP:ZCL_VE_GEN_BGPF'
  virtual bgpfstatusdescription : ze_bgpf_status_description,
          @ObjectModel.virtualElementCalculatedBy: 'ABAP:ZCL_VE_GEN_BGPF'
  virtual BGPFStatusCriticality : ze_bgpf_status_criticality,
          message,
          EBSTrigger,
          bgPFName,
          bgPFMonitor,
          CreatedBy,
          CreatedAt,
          LastChangedBy,
          LastChangedAt,
          /* Associations */
          _FEBP : redirected to composition child ZC_FEBP,
          _Log
}
