
#ifndef FRAMELABEL_H
#define FRAMELABEL_H

#include <QLabel>
#include <QPoint>

#include "Structures.h"

class QRect;
class QMenu;

class FrameLabel : public QLabel
{
    Q_OBJECT

    public:
        FrameLabel(QWidget *parent = 0);
        void setMouseCursorPos(QPoint point);
        QPoint getMouseCursorPos();
        QMenu *menu;

    private:
        void createContextMenu();
        MouseData m_mouseData;
        QPoint m_startPoint;
        QPoint m_mouseCursorPos;
        bool m_drawBox;
        QRect *m_box;

    protected:
        void mouseMoveEvent(QMouseEvent *ev);
        void mousePressEvent(QMouseEvent *ev);
        void mouseReleaseEvent(QMouseEvent *ev);
        void paintEvent(QPaintEvent *ev);

    signals:
        void newMouseData(MouseData mouseData);
        void onMouseMoveEvent();
};

#endif // FRAMELABEL_H
