//CrossTopicDiffPlugin update_topic_diff_status.js
//
var ctdpRestHandlerUrl;
var ctdpCompareList;
var ctdpWeb1;
var ctdpWeb2;

function ctdpEl(id) {
	if (document.getElementById) {
		return document.getElementById(id);
	} else if (window[id]) {
		return window[id];
	}
	return null;
}

function ctdpUpdateCompareStatuses() {
	setTimeout(ctdpUpdateWorker, 500);
	//addLoadEvent(ctdpUpdateWorker);
}

function ctdpUpdateWorker() {
	for (var topic in ctdpCompareList) {
		ctdpUpdateDiffStatus(ctdpWeb1, ctdpCompareList[topic], ctdpWeb2, ctdpCompareList[topic], "Status_" + ctdpCompareList[topic]);
	}
}

function ctdpUpdateDiffStatus(w1, t1, w2, t2, id)
{
	var statusText = ctdpEl(id);
	if (!statusText) {
		return;
	}
	var diffStatus;
	function onSuccess(text,req,o)
	{
		diffStatus = text;
	}
	function onError(text, req, o)
	{
		diffStatus = "FAILED: "+text;
	}
	tinymce.util.XHR.send({url: ctdpRestHandlerUrl,
                           content_type: "application/x-www-form-urlencoded",
                           type: "POST",
                           data: "web1=" + w1 + "&topic1=" + t1
                               + "&web2=" + w2 + "&topic2=" + t2,
			               async:false,
	                       success:onSuccess,
	                       error:onError});
	statusText.innerHTML = diffStatus;
}
