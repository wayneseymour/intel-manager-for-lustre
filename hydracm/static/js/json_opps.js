var ERR_COMMON_DELETE_HOST = "Error in deleting host: ";
var ERR_COMMON_LNET_STATUS = "Error in setting lnet status: ";
var ERR_COMMON_ADD_HOST = "Error in Adding host: ";
var ERR_COMMON_FS = "Error in creating File System";
var ERR_COMMON_CREATE_OST = "Error in Creating OST";
var ERR_COMMON_CREATE_MGT = "Error in Creating MGT";
var ERR_COMMON_CREATE_MDT = "Error in Creating MDT: ";
var ERR_COMMON_START_OST = "Error in Starting OST: ";
var ERR_CONFIF_PARAM = "Error in setting Cofiguration Params: ";
var ERR_VOLUME_CONFIG = "Error in setting volume cofiguration ";

var ALERT_TITLE = "Configuration Manager";
var CONFIRM_TITLE = "Configuration Manager";

TransitionCommit = function(id, ct, state)
{
  invoke_api_call(api_post, "transition/", {id: id, content_type_id: ct, new_state: state}, function() {}, function() {});
}

$(document).ready(function() {
  $('#transition_confirmation_dialog').dialog({autoOpen: false, maxHeight: 400, maxWidth: 800, width: 'auto', height: 'auto'});
});

Transition = function (id, ct, state)
{
  invoke_api_call(api_post, "transition_consequences/", {id: id, content_type_id: ct, new_state: state}, 
  success_callback = function(data)  
  {
    var requires_confirmation = false;

    var confirmation_markup = "<p>This action will have the following consequences:</p><ul>";
    if (data.length > 1) {
    $.each(data, function(i, consequence_info) {
      confirmation_markup += "<li>" + consequence_info.description + "</li>";
      if (consequence_info.requires_confirmation) {
        requires_confirmation = true;
      }
    });
    confirmation_markup += "</ul>"
    } else {
      requires_confirmation = data[0].requires_confirmation;
      confirmation_markup = "<p><strong>" + data[0].description + "</strong></p><p>Are you sure?</p>";
    }

    if (requires_confirmation) {
     $('#transition_confirmation_dialog').html(confirmation_markup);
     $('#transition_confirmation_dialog').dialog('option', 'buttons', {
       'Cancel': function() {$(this).dialog('close');},
       'Confirm': function() {TransitionCommit(id, ct, state);$(this).dialog('close');}
     });
     $('#transition_confirmation_dialog').dialog('open');
    } else {
      TransitionCommit(id, ct, state);
    }
  });
}

function Add_Host_Table(dialog_id)
{
  //$('#host_status').remove();
  $('#status_tab').empty();
  $('#host_status').empty();
  var oTable = "<table width='100%' border='0' cellspacing='0' cellpadding='0' id='hostdetails'><tr><td width='41%' align='right' valign='middle'>Host name:</td><td width='60%' align='left' valign='middle'><input type='text' name='txtHostName' id='txtHostName' /></td></tr></table>";
  $("#" + dialog_id).dialog("option", "buttons", null);
      
  $("#" + dialog_id).dialog({ 
    buttons: { 
      "Close": function() { 
            $(this).dialog("close");
          },
      "Continue": function() {
        AddHost_ServerConfig($('#txtHostName').val(),dialog_id);
      }
    }
  });
      
  $('#hostdetails_container').html(oTable);
}

function CreateFS(fsname, mgt_id, mgt_lun_id, mdt_lun_id, ost_lun_ids, success, config_json)
{
  var conf_params;
  if(JSON.stringify(config_json) == '{}')
    conf_params = "";
  else
    conf_params = config_json;

  var api_params = {
      "fsname":fsname,
      "mgt_id":mgt_id,
      "mgt_lun_id":mgt_lun_id,
      "mdt_lun_id":mdt_lun_id,
      "ost_lun_ids": ost_lun_ids,
      "conf_params": conf_params
  };
  
  invoke_api_call(api_post, "filesystem/", api_params,
  success_callback = function(data)
  {
    var fs_id = data.id;    
    if (success) {
      success(fs_id);
    }
  },
  error_callback = function(data){
    jAlert(ERR_COMMON_FS, ALERT_TITLE);
  });
}

function CreateOSTs(fs_id, ost_lun_ids)
{
  invoke_api_call(api_post, "target/", {kind: 'OST', filesystem_id: fs_id, lun_ids: ost_lun_ids},
  success_callback = function(data)
  {
    //Reload table with latest ost's.
    LoadTargets_EditFS(fs_id);
  },
  error_callback = function(data){
    jAlert(ERR_COMMON_CREATE_OST, ALERT_TITLE);
  });
}

function CreateMGT(lun_id, callback)
{
  invoke_api_call(api_post, "target/", {kind: 'MGT', lun_ids: [lun_id]},
  success_callback = function(data)
  {
    callback();
  },
  error_callback = function(data)
  {
    jAlert(ERR_COMMON_CREATE_MGT, ALERT_TITLE);
  });
}

function GetConfigurationParam(target_id, kinds, table_id)
{
  $('#' + table_id).dataTable().fnClearTable();
  var api_params = {
      "target_id": target_id,
      "kinds": kinds
  };
  
  invoke_api_call(api_post, "get_conf_params/", api_params, 
  success_callback = function(data)
  {
    CreateTable_FS_Config_Param(data, table_id);
  },
  error_callback = function(data)
  {
    if(data.errors != undefined)
    {
      jAlert(ERR_COMMON_START_OST + data.errors, ALERT_TITLE);
    }
  });
}

function CreateTable_FS_Config_Param(data, table_id)
{
  var property_box="";
  var text_index = 0;
  $.each(data, function(resKey, resValue)
  {   
    property_box = "<input type=textbox value='" + resValue.value + "' id='" + text_index + 
    "' title='" + resValue.conf_param_help + "' onblur='validateNumber("+text_index+")'/>"; 
    text_index++;
    $('#' + table_id).dataTable().fnAddData ([
      resValue.conf_param, 
      property_box,
      resValue.value
    ]);
  });
}

function validateNumber(obj_id)
{
    if (isNaN($("#"+obj_id).val()))
    {
        jAlert("Please enter numeric value");
        $("#"+obj_id).attr("value","");
        $("#"+obj_id).focus();
    }
}

function ApplyConfigParam(table_obj,target_id,target_dialog,isFS)
{
  var change_flag = false;
  var oSetting = table_obj.fnSettings();
  var config_json = {}
  for (var i=0, iLen=oSetting.aoData.length; i<iLen; i++) {
    if(oSetting.aoData[i]._aData[2] != $("input#"+i).val())
    {
       config_json[oSetting.aoData[i]._aData[0]] = $("input#"+i).val();
       change_flag = true;
    }
  }

  if(typeof(isFS) == "undefined")
    isFS = "";

  if(change_flag)
  {
    var api_params = {
        "target_id": target_id,
        "conf_params": config_json,
        "IsFS": isFS
    };

    invoke_api_call(api_post, "set_conf_params/", api_params, 
    success_callback = function(data)
    {
      jAlert("Update Successful");
    },
    error_callback = function(data)
    {
      if(data.errors != undefined)
      {
        jAlert(ERR_CONFIF_PARAM + data.errors, ALERT_TITLE);
      }
    });

    $('#'+target_dialog).dialog('close'); 
  }
}

save_primary_failover_server = function (confirmation_markup, volumes)
{
   $('#transition_confirmation_dialog').html(confirmation_markup);
   $('#transition_confirmation_dialog').dialog('option', 'buttons', {
     'Cancel': function() {$(this).dialog('close');},
     'Confirm': 
     {
         text: "Confirm",
         id: "transition_confirm_button",
         click: function(){
           invoke_api_call(api_put, "volume/", volumes, 
           success_callback = function(data)
           {
             jAlert("Update Successful");
           },
           error_callback = function(data)
           {
             jAlert(ERR_VOLUME_CONFIG, ALERT_TITLE);
           });
           $(this).dialog('close');
         }
     } 
   });
   $('#transition_confirmation_dialog').dialog('open');
}
