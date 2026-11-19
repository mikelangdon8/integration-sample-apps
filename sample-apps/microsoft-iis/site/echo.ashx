<%@ WebHandler Language="C#" Class="EchoHandler" %>

using System;
using System.Net.WebSockets;
using System.Threading;
using System.Threading.Tasks;
using System.Web;
using System.Web.WebSockets;

public class EchoHandler : IHttpHandler
{
    public bool IsReusable { get { return false; } }

    public void ProcessRequest(HttpContext context)
    {
        if (context.IsWebSocketRequest)
        {
            context.AcceptWebSocketRequest(Echo);
        }
        else
        {
            context.Response.StatusCode = 400;
        }
    }

    private static async Task Echo(AspNetWebSocketContext context)
    {
        WebSocket socket = context.WebSocket;
        byte[] buffer = new byte[1024];
        while (socket.State == WebSocketState.Open)
        {
            WebSocketReceiveResult received = await socket.ReceiveAsync(new ArraySegment<byte>(buffer), CancellationToken.None);
            if (received.MessageType == WebSocketMessageType.Close)
            {
                await socket.CloseAsync(WebSocketCloseStatus.NormalClosure, "", CancellationToken.None);
                break;
            }
            await socket.SendAsync(new ArraySegment<byte>(buffer, 0, received.Count), received.MessageType, received.EndOfMessage, CancellationToken.None);
        }
    }
}
