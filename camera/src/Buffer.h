
#ifndef BUFFER_H
#define BUFFER_H

#include <QMutex>
#include <QQueue>
#include <QSemaphore>
#include <QByteArray>

template<class T> class Buffer
{
    public:
        Buffer(int size);
        void add(const T& data, bool dropIfFull = false);
        T get();
        bool clear();
        int size() const
        {
            return m_queue.size();
        }
        int maxSize() const
        {
            return m_bufferSize;
        }
        bool isFull() const
        {
            return m_queue.size() == m_bufferSize;
        }
        bool isEmpty() const
        {
            return m_queue.size() == 0;
        }

    private:
        QMutex m_queueProtectMutex;
        QQueue<T> m_queue;
        QSemaphore *m_freeSlotsSemaphore;
        QSemaphore *m_usedSlotsSemaphore;
        QSemaphore *m_addProtectSemaphore;
        QSemaphore *m_getProtectSemaphore;
        int m_bufferSize;
};

template<class T> Buffer<T>::Buffer(int size)
{
    // Save buffer size
    m_bufferSize = size;
    // Create semaphores
    m_freeSlotsSemaphore = new QSemaphore(m_bufferSize);
    m_usedSlotsSemaphore = new QSemaphore(0);
    m_addProtectSemaphore = new QSemaphore(1);
    m_getProtectSemaphore = new QSemaphore(1);
}

template<class T> void Buffer<T>::add(const T& data, bool dropIfFull)
{
    m_addProtectSemaphore->acquire();

    // If dropping is enabled, do not block if buffer is full
    if(dropIfFull)
    {
        // Try and acquire semaphore to add item
        if (m_freeSlotsSemaphore->tryAcquire())
        {
            // Add item to queue
            m_queueProtectMutex.lock();
            m_queue.enqueue(data);
            m_queueProtectMutex.unlock();
            // Release semaphore
            m_usedSlotsSemaphore->release();
        }
    }
    // If buffer is full, wait on semaphore
    else
    {
        // Acquire semaphore
        m_freeSlotsSemaphore->acquire();
        // Add item to queue
        m_queueProtectMutex.lock();
        m_queue.enqueue(data);
        m_queueProtectMutex.unlock();
        // Release semaphore
        m_usedSlotsSemaphore->release();
    }

    m_addProtectSemaphore->release();
}

template<class T> T Buffer<T>::get()
{
    T data;
    m_getProtectSemaphore->acquire();

    // Acquire semaphores
    m_usedSlotsSemaphore->acquire();
    // Take item from queue
    m_queueProtectMutex.lock();
    data = m_queue.dequeue();
    m_queueProtectMutex.unlock();
    // Release semaphores
    m_freeSlotsSemaphore->release();

    m_getProtectSemaphore->release();
    return data;
}

template<class T> bool Buffer<T>::clear()
{
    // Check if buffer contains items
    if (m_queue.size() > 0)
    {
        // Stop adding items to buffer (will return false if an item is currently being added to the buffer)
        if (m_addProtectSemaphore->tryAcquire())
        {
            // Stop taking items from buffer (will return false if an item is currently being taken from the buffer)
            if (m_getProtectSemaphore->tryAcquire())
            {
                // Release all remaining slots in queue
                m_freeSlotsSemaphore->release(m_queue.size());
                // Acquire all queue slots
                m_freeSlotsSemaphore->acquire(m_bufferSize);
                // Reset usedSlots to zero
                m_usedSlotsSemaphore->acquire(m_queue.size());
                // Clear buffer
                m_queue.clear();
                // Release all slots
                m_freeSlotsSemaphore->release(m_bufferSize);
                // Allow get method to resume
                m_getProtectSemaphore->release();
            }
            else
            {
                return false;
            }
            // Allow add method to resume
            m_addProtectSemaphore->release();
            return true;
        }
        else
        {
            return false;
        }
    }
    else
    {
        return false;
    }
}

#endif // BUFFER_H
