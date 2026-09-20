import QtQuick

Item {
    id: icon
    property string name: "session"
    property color color: "#b8c0bd"
    property real strokeWidth: 1.8

    implicitWidth: 24
    implicitHeight: 24

    onNameChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
    onStrokeWidthChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        function line(ctx, x1, y1, x2, y2) {
            ctx.beginPath(); ctx.moveTo(x1,y1); ctx.lineTo(x2,y2); ctx.stroke()
        }
        function rr(ctx, x, y, w, h, r) {
            ctx.beginPath()
            ctx.moveTo(x+r,y); ctx.lineTo(x+w-r,y); ctx.quadraticCurveTo(x+w,y,x+w,y+r)
            ctx.lineTo(x+w,y+h-r); ctx.quadraticCurveTo(x+w,y+h,x+w-r,y+h)
            ctx.lineTo(x+r,y+h); ctx.quadraticCurveTo(x,y+h,x,y+h-r)
            ctx.lineTo(x,y+r); ctx.quadraticCurveTo(x,y,x+r,y); ctx.stroke()
        }

        onPaint: {
            var ctx = getContext("2d")
            ctx.setTransform(1, 0, 0, 1, 0, 0)
            ctx.clearRect(0, 0, width, height)
            var sx = width / 24.0, sy = height / 24.0
            ctx.setTransform(sx, 0, 0, sy, 0, 0)
            ctx.strokeStyle = icon.color
            ctx.fillStyle = icon.color
            ctx.lineWidth = icon.strokeWidth
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            if (icon.name === "session") {
                rr(ctx, 3, 4, 14, 11, 2)
                line(ctx, 7, 19, 13, 19); line(ctx, 10, 15, 10, 19)
                ctx.beginPath(); ctx.arc(18,17,4,0,Math.PI*2); ctx.stroke()
                line(ctx,18,15,18,19); line(ctx,16,17,20,17)
            } else if (icon.name === "files" || icon.name === "ftp" || icon.name === "sftp") {
                ctx.beginPath(); ctx.moveTo(2.5,7); ctx.lineTo(9,7); ctx.lineTo(11,9); ctx.lineTo(21.5,9)
                ctx.lineTo(20,19); ctx.lineTo(4,19); ctx.closePath(); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(3.5,7); ctx.lineTo(4.5,5); ctx.lineTo(9,5); ctx.lineTo(11,7); ctx.stroke()
                if (icon.name === "sftp") { line(ctx,15,12,15,17); line(ctx,13.2,13.8,15,12); line(ctx,16.8,13.8,15,12) }
                if (icon.name === "ftp") { line(ctx,15,12,15,17); line(ctx,13.2,15.2,15,17); line(ctx,16.8,15.2,15,17) }
            } else if (icon.name === "fullscreen") {
                line(ctx,4,9,4,4); line(ctx,4,4,9,4); line(ctx,15,4,20,4); line(ctx,20,4,20,9)
                line(ctx,4,15,4,20); line(ctx,4,20,9,20); line(ctx,15,20,20,20); line(ctx,20,20,20,15)
            } else if (icon.name === "disconnect") {
                ctx.beginPath(); ctx.arc(12,13,7,Math.PI*1.22,Math.PI*1.78,false); ctx.stroke()
                ctx.beginPath(); ctx.arc(12,13,7,Math.PI*1.78,Math.PI*3.22,false); ctx.stroke()
                line(ctx,12,3,12,11)
            } else if (icon.name === "info") {
                ctx.beginPath(); ctx.arc(12,12,9,0,Math.PI*2); ctx.stroke()
                ctx.beginPath(); ctx.arc(12,7.5,1,0,Math.PI*2); ctx.fill()
                line(ctx,12,11,12,17)
            } else if (icon.name === "home") {
                ctx.beginPath(); ctx.moveTo(3,11); ctx.lineTo(12,4); ctx.lineTo(21,11); ctx.stroke()
                ctx.beginPath(); ctx.moveTo(6,10); ctx.lineTo(6,20); ctx.lineTo(18,20); ctx.lineTo(18,10); ctx.stroke()
            } else if (icon.name === "rdp") {
                rr(ctx, 2.5, 4, 19, 13, 2)
                line(ctx,8,21,16,21); line(ctx,12,17,12,21)
                ctx.beginPath(); ctx.arc(18,7.5,1.5,0,Math.PI*2); ctx.fill()
            } else if (icon.name === "ssh" || icon.name === "terminal") {
                rr(ctx, 2.5, 4, 19, 16, 2)
                line(ctx,6.5,9,9.5,12); line(ctx,9.5,12,6.5,15); line(ctx,12,15,17,15)
            } else if (icon.name === "close") {
                line(ctx,7,7,17,17); line(ctx,17,7,7,17)
            } else if (icon.name === "plus") {
                line(ctx,12,5,12,19); line(ctx,5,12,19,12)
            } else if (icon.name === "lock") {
                rr(ctx, 5, 10, 14, 10, 2)
                ctx.beginPath(); ctx.arc(12,10,4.5,Math.PI,0,false); ctx.stroke()
                line(ctx,12,14,12,17)
            } else {
                ctx.beginPath(); ctx.arc(12,12,7,0,Math.PI*2); ctx.stroke()
            }
        }
    }
}
