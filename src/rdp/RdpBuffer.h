#pragma once

#include <QByteArray>
#include <QtEndian>
#include <QtGlobal>
#include <cstring>

namespace Rdp {

class Writer
{
public:
    explicit Writer(int reserve = 256) { m_data.reserve(reserve); }

    QByteArray &data() { return m_data; }
    const QByteArray &data() const { return m_data; }
    int size() const { return m_data.size(); }

    void u8(quint8 v) { m_data.append(char(v)); }
    void u16(quint16 v)
    {
        const quint16 le = qToLittleEndian(v);
        m_data.append(reinterpret_cast<const char *>(&le), 2);
    }
    void u32(quint32 v)
    {
        const quint32 le = qToLittleEndian(v);
        m_data.append(reinterpret_cast<const char *>(&le), 4);
    }
    void u16Be(quint16 v)
    {
        const quint16 be = qToBigEndian(v);
        m_data.append(reinterpret_cast<const char *>(&be), 2);
    }
    void bytes(const QByteArray &b) { m_data.append(b); }
    void bytes(const char *p, int n) { m_data.append(p, n); }
    void zero(int n) { m_data.append(QByteArray(n, '\0')); }

    void utf16z(const QString &text, int fixedChars = 0)
    {
        const QString truncated = fixedChars > 0 ? text.left(fixedChars - 1) : text;
        for (QChar ch : truncated) {
            u16(quint16(ch.unicode()));
        }
        u16(0);
        if (fixedChars > 0) {
            const int writtenChars = truncated.size() + 1;
            if (writtenChars < fixedChars)
                zero((fixedChars - writtenChars) * 2);
        }
    }

    void patchU16(int offset, quint16 v)
    {
        const quint16 le = qToLittleEndian(v);
        m_data[offset] = char(reinterpret_cast<const uchar *>(&le)[0]);
        m_data[offset + 1] = char(reinterpret_cast<const uchar *>(&le)[1]);
    }

    void patchU32(int offset, quint32 v)
    {
        const quint32 le = qToLittleEndian(v);
        memcpy(m_data.data() + offset, &le, 4);
    }

private:
    QByteArray m_data;
};

class Reader
{
public:
    explicit Reader(const QByteArray &data)
        : m_data(data)
    {
    }

    bool ok() const { return m_ok && m_pos <= m_data.size(); }
    int pos() const { return m_pos; }
    int remaining() const { return m_data.size() - m_pos; }
    const QByteArray &raw() const { return m_data; }

    quint8 u8()
    {
        if (m_pos + 1 > m_data.size()) {
            m_ok = false;
            return 0;
        }
        return uchar(m_data.at(m_pos++));
    }

    quint16 u16()
    {
        if (m_pos + 2 > m_data.size()) {
            m_ok = false;
            return 0;
        }
        quint16 v = 0;
        memcpy(&v, m_data.constData() + m_pos, 2);
        m_pos += 2;
        return qFromLittleEndian(v);
    }

    quint32 u32()
    {
        if (m_pos + 4 > m_data.size()) {
            m_ok = false;
            return 0;
        }
        quint32 v = 0;
        memcpy(&v, m_data.constData() + m_pos, 4);
        m_pos += 4;
        return qFromLittleEndian(v);
    }

    quint16 u16Be()
    {
        if (m_pos + 2 > m_data.size()) {
            m_ok = false;
            return 0;
        }
        quint16 v = 0;
        memcpy(&v, m_data.constData() + m_pos, 2);
        m_pos += 2;
        return qFromBigEndian(v);
    }

    QByteArray take(int n)
    {
        if (n < 0 || m_pos + n > m_data.size()) {
            m_ok = false;
            return {};
        }
        const QByteArray out = m_data.mid(m_pos, n);
        m_pos += n;
        return out;
    }

    void skip(int n)
    {
        if (n < 0 || m_pos + n > m_data.size()) {
            m_ok = false;
            return;
        }
        m_pos += n;
    }

private:
    QByteArray m_data;
    int m_pos = 0;
    bool m_ok = true;
};

inline QByteArray wrapTpkt(const QByteArray &payload)
{
    Writer w(payload.size() + 4);
    w.u8(0x03);
    w.u8(0x00);
    w.u16Be(quint16(payload.size() + 4));
    w.bytes(payload);
    return w.data();
}

} // namespace Rdp
