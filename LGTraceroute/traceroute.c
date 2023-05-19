//
//  traceroute.c
//  LGTraceroute
//
//  Created by admin on 2023/5/17.
//

#include "traceroute.h"

#include <sys/param.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <sys/file.h>
#include <sys/ioctl.h>

#include <netinet/in_systm.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/ip_icmp.h>
#include <netinet/udp.h>

#include <arpa/inet.h>

#include <netdb.h>
#include <stdio.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define    MAXPACKET    65535    /* max ip packet size */
#ifndef MAXHOSTNAMELEN
#define MAXHOSTNAMELEN    64
#endif

#ifndef FD_SET
#define NFDBITS         (8*sizeof(fd_set))
#define FD_SETSIZE      NFDBITS
#define FD_SET(n, p)    ((p)->fds_bits[(n)/NFDBITS] |= (1 << ((n) % NFDBITS)))
#define FD_CLR(n, p)    ((p)->fds_bits[(n)/NFDBITS] &= ~(1 << ((n) % NFDBITS)))
#define FD_ISSET(n, p)  ((p)->fds_bits[(n)/NFDBITS] & (1 << ((n) % NFDBITS)))
#define FD_ZERO(p)      bzero((char *)(p), sizeof(*(p)))
#endif

#define Fprintf (void)fprintf
#define Sprintf (void)sprintf
#define Printf (void)printf

/*
 * format of a (udp) probe packet.
 */
struct opacket {
    struct ip ip;
    struct udphdr udp;
    u_char seq;        /* sequence number of this packet */
    u_char ttl;        /* ttl packet left with */
    struct timeval tv;    /* time packet left */
};

u_char    packet[512];        /* last inbound (icmp) packet */
struct opacket    *outpacket;    /* last output (udp) packet */

int wait_for_reply __P((int, struct sockaddr_in *));
void send_probe __P((int, int));
double deltaT __P((struct timeval *, struct timeval *));
int packet_ok __P((u_char *, int, struct sockaddr_in *, int));
void print __P((u_char *, int, struct sockaddr_in *));
void tvsub __P((struct timeval *, struct timeval *));
char *inetname __P((struct in_addr));
void usage __P(());

int s;                /* receive (icmp) socket file descriptor */
int sndsock;            /* send (udp) socket file descriptor */
struct timezone tz;        /* leftover */

struct sockaddr whereto;    /* Who to try to reach */
int datalen;            /* How much data */

char *source = 0;
char *hostname;

int nprobes = 3;
int max_ttl = 30;
u_short ident;
u_short port = 32768+666;    /* start udp dest port # for probe packets */
int options;            /* socket options */
int verbose;
int waittime = 5;        /* time to wait for response (in seconds) */
int nflag;            /* print addresses numerically */

int
traceroute(int argc, char *argv[])
{
    extern char *optarg;
    extern int optind;
    struct hostent *hp;
    struct protoent *pe;
    struct sockaddr_in from, *to;
    int ch, i, on, probe, seq, tos, ttl;

    on = 1;
    seq = tos = 0;
    to = (struct sockaddr_in *)&whereto;
    while ((ch = getopt(argc, argv, "dm:np:q:rs:t:w:v")) != EOF)
        switch(ch) {
        case 'd':
            options |= SO_DEBUG;
            break;
        case 'm':
            max_ttl = atoi(optarg);
            if (max_ttl <= 1) {
                Fprintf(stderr,
                    "traceroute: max ttl must be >1.\n");
                exit(1);
            }
            break;
        case 'n':
            nflag++;
            break;
        case 'p':
            port = atoi(optarg);
            if (port < 1) {
                Fprintf(stderr,
                    "traceroute: port must be >0.\n");
                exit(1);
            }
            break;
        case 'q':
            nprobes = atoi(optarg);
            if (nprobes < 1) {
                Fprintf(stderr,
                    "traceroute: nprobes must be >0.\n");
                exit(1);
            }
            break;
        case 'r':
            options |= SO_DONTROUTE;
            break;
        case 's':
            /*
             * set the ip source address of the outbound
             * probe (e.g., on a multi-homed host).
             */
            source = optarg;
            break;
        case 't':
            tos = atoi(optarg);
            if (tos < 0 || tos > 255) {
                Fprintf(stderr,
                    "traceroute: tos must be 0 to 255.\n");
                exit(1);
            }
            break;
        case 'v':
            verbose++;
            break;
        case 'w':
            waittime = atoi(optarg);
            if (waittime <= 1) {
                Fprintf(stderr,
                    "traceroute: wait must be >1 sec.\n");
                exit(1);
            }
            break;
        default:
            usage();
        }
    argc -= optind;
    argv += optind;

    if (argc < 1)
        usage();

    setlinebuf (stdout);

    (void) bzero((char *)&whereto, sizeof(struct sockaddr));
    to->sin_family = AF_INET;
    to->sin_addr.s_addr = inet_addr(*argv);
    if (to->sin_addr.s_addr != -1)
        hostname = *argv;
    else {
        hp = gethostbyname(*argv);
        if (hp) {
            to->sin_family = hp->h_addrtype;
            bcopy(hp->h_addr, (caddr_t)&to->sin_addr, hp->h_length);
            hostname = hp->h_name;
        } else {
            (void)fprintf(stderr,
                "traceroute: unknown host %s\n", *argv);
            exit(1);
        }
    }
    if (*++argv)
        datalen = atoi(*argv);
    if (datalen < 0 || datalen >= MAXPACKET - sizeof(struct opacket)) {
        Fprintf(stderr,
            "traceroute: packet size must be 0 <= s < %ld.\n",
            MAXPACKET - sizeof(struct opacket));
        exit(1);
    }
    datalen += sizeof(struct opacket);
    outpacket = (struct opacket *)malloc((unsigned)datalen);
    if (! outpacket) {
        perror("traceroute: malloc");
        exit(1);
    }
    (void) bzero((char *)outpacket, datalen);
    outpacket->ip.ip_dst = to->sin_addr;
    outpacket->ip.ip_tos = tos;
    outpacket->ip.ip_v = IPVERSION;
    outpacket->ip.ip_id = 0;

    ident = (getpid() & 0xffff) | 0x8000;

    if ((pe = getprotobyname("udp")) == NULL) {
        Fprintf(stderr, "udp: unknown protocol\n");
        exit(10);
    }
    if ((s = socket(AF_INET, SOCK_RAW, pe->p_proto)) < 0) {
        perror("traceroute: udp socket");
        exit(5);
    }
    
    /*
    if ((pe = getprotobyname("icmp")) == NULL) {
        Fprintf(stderr, "icmp: unknown protocol\n");
        exit(10);
    }
    if ((s = socket(AF_INET, SOCK_RAW, pe->p_proto)) < 0) {
        perror("traceroute: icmp socket");
        exit(5);
    }
    */
    
    if (options & SO_DEBUG)
        (void) setsockopt(s, SOL_SOCKET, SO_DEBUG,
                  (char *)&on, sizeof(on));
    if (options & SO_DONTROUTE)
        (void) setsockopt(s, SOL_SOCKET, SO_DONTROUTE,
                  (char *)&on, sizeof(on));

    if ((sndsock = socket(AF_INET, SOCK_RAW, IPPROTO_RAW)) < 0) {
        perror("traceroute: raw socket");
        exit(5);
    }
#ifdef SO_SNDBUF
    if (setsockopt(sndsock, SOL_SOCKET, SO_SNDBUF, (char *)&datalen,
               sizeof(datalen)) < 0) {
        perror("traceroute: SO_SNDBUF");
        exit(6);
    }
#endif SO_SNDBUF
#ifdef IP_HDRINCL
    if (setsockopt(sndsock, IPPROTO_IP, IP_HDRINCL, (char *)&on,
               sizeof(on)) < 0) {
        perror("traceroute: IP_HDRINCL");
        exit(6);
    }
#endif IP_HDRINCL
    if (options & SO_DEBUG)
        (void) setsockopt(sndsock, SOL_SOCKET, SO_DEBUG,
                  (char *)&on, sizeof(on));
    if (options & SO_DONTROUTE)
        (void) setsockopt(sndsock, SOL_SOCKET, SO_DONTROUTE,
                  (char *)&on, sizeof(on));

    if (source) {
        (void) bzero((char *)&from, sizeof(struct sockaddr));
        from.sin_family = AF_INET;
        from.sin_addr.s_addr = inet_addr(source);
        if (from.sin_addr.s_addr == -1) {
            Printf("traceroute: unknown host %s\n", source);
            exit(1);
        }
        outpacket->ip.ip_src = from.sin_addr;
#ifndef IP_HDRINCL
        if (bind(sndsock, (struct sockaddr *)&from, sizeof(from)) < 0) {
            perror ("traceroute: bind:");
            exit (1);
        }
#endif IP_HDRINCL
    }

    Fprintf(stderr, "traceroute to %s (%s)", hostname,
        inet_ntoa(to->sin_addr));
    if (source)
        Fprintf(stderr, " from %s", source);
    Fprintf(stderr, ", %d hops max, %d byte packets\n", max_ttl, datalen);
    (void) fflush(stderr);

    for (ttl = 1; ttl <= max_ttl; ++ttl) {
        u_long lastaddr = 0;
        int got_there = 0;
        int unreachable = 0;

        Printf("%2d ", ttl);
        for (probe = 0; probe < nprobes; ++probe) {
            int cc;
            struct timeval t1, t2;
            struct timezone tz;
            struct ip *ip;

            (void) gettimeofday(&t1, &tz);
            send_probe(++seq, ttl);
            while (cc = wait_for_reply(s, &from)) {
                (void) gettimeofday(&t2, &tz);
                if ((i = packet_ok(packet, cc, &from, seq))) {
                    if (from.sin_addr.s_addr != lastaddr) {
                        print(packet, cc, &from);
                        lastaddr = from.sin_addr.s_addr;
                    }
                    Printf("  %g ms", deltaT(&t1, &t2));
                    switch(i - 1) {
                    case ICMP_UNREACH_PORT:
#ifndef ARCHAIC
                        ip = (struct ip *)packet;
                        if (ip->ip_ttl <= 1)
                            Printf(" !");
#endif ARCHAIC
                        ++got_there;
                        break;
                    case ICMP_UNREACH_NET:
                        ++unreachable;
                        Printf(" !N");
                        break;
                    case ICMP_UNREACH_HOST:
                        ++unreachable;
                        Printf(" !H");
                        break;
                    case ICMP_UNREACH_PROTOCOL:
                        ++got_there;
                        Printf(" !P");
                        break;
                    case ICMP_UNREACH_NEEDFRAG:
                        ++unreachable;
                        Printf(" !F");
                        break;
                    case ICMP_UNREACH_SRCFAIL:
                        ++unreachable;
                        Printf(" !S");
                        break;
                    }
                    break;
                }
            }
            if (cc == 0)
                Printf(" *");
            (void) fflush(stdout);
        }
        putchar('\n');
        if (got_there || unreachable >= nprobes-1)
            exit(0);
    }
    
    return 0;
}

int
wait_for_reply(sock, from)
    int sock;
    struct sockaddr_in *from;
{
    fd_set fds;
    struct timeval wait;
    int cc = 0;
    int fromlen = sizeof (*from);

    FD_ZERO(&fds);
    FD_SET(sock, &fds);
    wait.tv_sec = waittime; wait.tv_usec = 0;

    if (select(sock+1, &fds, (fd_set *)0, (fd_set *)0, &wait) > 0)
        cc=recvfrom(s, (char *)packet, sizeof(packet), 0,
                (struct sockaddr *)from, &fromlen);

    return(cc);
}


void
send_probe(seq, ttl)
    int seq, ttl;
{
    struct opacket *op = outpacket;
    struct ip *ip = &op->ip;
    struct udphdr *up = &op->udp;
    int i;

    ip->ip_off = 0;
    ip->ip_hl = sizeof(*ip) >> 2;
    ip->ip_p = IPPROTO_UDP;
    ip->ip_len = datalen;
    ip->ip_ttl = ttl;
    ip->ip_v = IPVERSION;
    ip->ip_id = htons(ident+seq);

    up->uh_sport = htons(ident);
    up->uh_dport = htons(port+seq);
    up->uh_ulen = htons((u_short)(datalen - sizeof(struct ip)));
    up->uh_sum = 0;

    op->seq = seq;
    op->ttl = ttl;
    (void) gettimeofday(&op->tv, &tz);

    i = sendto(sndsock, (char *)outpacket, datalen, 0, &whereto,
           sizeof(struct sockaddr));
    if (i < 0 || i != datalen)  {
        if (i<0)
            perror("sendto");
        Printf("traceroute: wrote %s %d chars, ret=%d\n", hostname,
            datalen, i);
        (void) fflush(stdout);
    }
}


double
deltaT(t1p, t2p)
    struct timeval *t1p, *t2p;
{
    register double dt;

    dt = (double)(t2p->tv_sec - t1p->tv_sec) * 1000.0 +
         (double)(t2p->tv_usec - t1p->tv_usec) / 1000.0;
    return (dt);
}


/*
 * Convert an ICMP "type" field to a printable string.
 */
char *
pr_type(t)
    u_char t;
{
    static char *ttab[] = {
    "Echo Reply",    "ICMP 1",    "ICMP 2",    "Dest Unreachable",
    "Source Quench", "Redirect",    "ICMP 6",    "ICMP 7",
    "Echo",        "ICMP 9",    "ICMP 10",    "Time Exceeded",
    "Param Problem", "Timestamp",    "Timestamp Reply", "Info Request",
    "Info Reply"
    };

    if(t > 16)
        return("OUT-OF-RANGE");

    return(ttab[t]);
}


int
packet_ok(buf, cc, from, seq)
    u_char *buf;
    int cc;
    struct sockaddr_in *from;
    int seq;
{
    register struct icmp *icp;
    u_char type, code;
    int hlen;
#ifndef ARCHAIC
    struct ip *ip;

    ip = (struct ip *) buf;
    hlen = ip->ip_hl << 2;
    if (cc < hlen + ICMP_MINLEN) {
        if (verbose)
            Printf("packet too short (%d bytes) from %s\n", cc,
                inet_ntoa(from->sin_addr));
        return (0);
    }
    cc -= hlen;
    icp = (struct icmp *)(buf + hlen);
#else
    icp = (struct icmp *)buf;
#endif ARCHAIC
    type = icp->icmp_type; code = icp->icmp_code;
    if ((type == ICMP_TIMXCEED && code == ICMP_TIMXCEED_INTRANS) ||
        type == ICMP_UNREACH) {
        struct ip *hip;
        struct udphdr *up;

        hip = &icp->icmp_ip;
        hlen = hip->ip_hl << 2;
        up = (struct udphdr *)((u_char *)hip + hlen);
        if (hlen + 12 <= cc && hip->ip_p == IPPROTO_UDP &&
            up->uh_sport == htons(ident) &&
            up->uh_dport == htons(port+seq))
            return (type == ICMP_TIMXCEED? -1 : code+1);
    }
#ifndef ARCHAIC
    if (verbose) {
        int i;
        u_long *lp = (u_long *)&icp->icmp_ip;

        Printf("\n%d bytes from %s to %s", cc,
            inet_ntoa(from->sin_addr), inet_ntoa(ip->ip_dst));
        Printf(": icmp type %d (%s) code %d\n", type, pr_type(type),
               icp->icmp_code);
        for (i = 4; i < cc ; i += sizeof(long))
            Printf("%2d: x%8.8lx\n", i, *lp++);
    }
#endif ARCHAIC
    return(0);
}


void
print(buf, cc, from)
    u_char *buf;
    int cc;
    struct sockaddr_in *from;
{
    struct ip *ip;
    int hlen;

    ip = (struct ip *) buf;
    hlen = ip->ip_hl << 2;
    cc -= hlen;

    if (nflag)
        Printf(" %s", inet_ntoa(from->sin_addr));
    else
        Printf(" %s (%s)", inetname(from->sin_addr),
               inet_ntoa(from->sin_addr));

    if (verbose)
        Printf (" %d bytes to %s", cc, inet_ntoa (ip->ip_dst));
}


#ifdef notyet
/*
 * Checksum routine for Internet Protocol family headers (C Version)
 */
u_short
in_cksum(addr, len)
    u_short *addr;
    int len;
{
    register int nleft = len;
    register u_short *w = addr;
    register u_short answer;
    register int sum = 0;

    /*
     *  Our algorithm is simple, using a 32 bit accumulator (sum),
     *  we add sequential 16 bit words to it, and at the end, fold
     *  back all the carry bits from the top 16 bits into the lower
     *  16 bits.
     */
    while (nleft > 1)  {
        sum += *w++;
        nleft -= 2;
    }

    /* mop up an odd byte, if necessary */
    if (nleft == 1)
        sum += *(u_char *)w;

    /*
     * add back carry outs from top 16 bits to low 16 bits
     */
    sum = (sum >> 16) + (sum & 0xffff);    /* add hi 16 to low 16 */
    sum += (sum >> 16);            /* add carry */
    answer = ~sum;                /* truncate to 16 bits */
    return (answer);
}
#endif notyet

/*
 * Subtract 2 timeval structs:  out = out - in.
 * Out is assumed to be >= in.
 */
void
tvsub(out, in)
    register struct timeval *out, *in;
{
    if ((out->tv_usec -= in->tv_usec) < 0)   {
        out->tv_sec--;
        out->tv_usec += 1000000;
    }
    out->tv_sec -= in->tv_sec;
}


/*
 * Construct an Internet address representation.
 * If the nflag has been supplied, give
 * numeric value, otherwise try for symbolic name.
 */
char *
inetname(in)
    struct in_addr in;
{
    register char *cp;
    static char line[50];
    struct hostent *hp;
    static char domain[MAXHOSTNAMELEN + 1];
    static int first = 1;

    if (first && !nflag) {
        first = 0;
        if (gethostname(domain, MAXHOSTNAMELEN) == 0 &&
            (cp = index(domain, '.')))
            (void) strcpy(domain, cp + 1);
        else
            domain[0] = 0;
    }
    cp = 0;
    if (!nflag && in.s_addr != INADDR_ANY) {
        hp = gethostbyaddr((char *)&in, sizeof (in), AF_INET);
        if (hp) {
            if ((cp = index(hp->h_name, '.')) &&
                !strcmp(cp + 1, domain))
                *cp = 0;
            cp = hp->h_name;
        }
    }
    if (cp)
        (void) strcpy(line, cp);
    else {
        in.s_addr = ntohl(in.s_addr);
#define C(x)    ((x) & 0xff)
        Sprintf(line, "%lu.%lu.%lu.%lu", C(in.s_addr >> 24),
            C(in.s_addr >> 16), C(in.s_addr >> 8), C(in.s_addr));
    }
    return (line);
}

void
usage()
{
    (void)fprintf(stderr,
"usage: traceroute [-dnrv] [-m max_ttl] [-p port#] [-q nqueries]\n\t\
[-s src_addr] [-t tos] [-w wait] host [data size]\n");
    exit(1);
}
