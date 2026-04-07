const re = /(?:https?:\/\/[^\s<>]+|(?:^|\s)(\/(?:promotion|promo-payment|verification|service-request|provider|provider-orders|subscription|chats|chat)(?:\/[^\s<>]*)?))/gi;
['javascript:alert(1)','data:text/html,<h1>xss</h1>'].forEach(t => { re.lastIndex=0; const m=re.exec(t); console.log(t,'->',m?'MATCH:'+m[0]:'SAFE'); });
['/promotion/?request_id=28','https://nawafeth.com/pay/','plain text no link'].forEach(t => { re.lastIndex=0; const m=re.exec(t); console.log(t,'->',m?'OK:'+m[0].trim():'NO_MATCH'); });
