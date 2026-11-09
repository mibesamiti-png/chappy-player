import 'dart:convert';
import 'dart:typed_data';

/// Offline user-provided classic PCAP inspection only. No live capture, MITM,
/// TLS decryption, remote control or mini-app JavaScript privilege.
class PcapObservation {
  final String sourceIp, destinationIp, protocol, description;
  final int sourcePort, destinationPort;
  final String? hostHint, plaintextPreview;
  final bool encrypted;
  const PcapObservation({
    required this.sourceIp, required this.destinationIp,
    required this.sourcePort, required this.destinationPort,
    required this.protocol, required this.description,
    required this.hostHint, required this.plaintextPreview,
    required this.encrypted,
  });
}

class PcapInspection {
  final int packetCount;
  final bool truncated, showsPlaintext;
  final List<PcapObservation> observations;
  const PcapInspection._(
      this.packetCount, this.truncated, this.showsPlaintext, this.observations);
}

/// Supports RFC791 IPv4, TCP/UDP, UDP DNS questions, one-packet TLS SNI,
/// plaintext HTTP request line/Host and opt-in safe-text body preview.
/// Does not reconstruct TCP streams, infer sites from IPs or read HTTPS bodies.
class PcapInspector {
  static const maxFileBytes = 2 * 1024 * 1024;
  static const maxPacketCount = 2500;
  static const maxVisible = 160;

  static int _u16(Uint8List b, int p, bool le) =>
      le ? (b[p] | b[p+1] << 8) : (b[p] << 8 | b[p+1]);
  static int _u32(Uint8List b, int p, bool le) =>
      (le ? b[p] | b[p+1] << 8 | b[p+2] << 16 | b[p+3] << 24
          : b[p] << 24 | b[p+1] << 16 | b[p+2] << 8 | b[p+3]) & 0xffffffff;
  static String _ip(Uint8List b, int p) =>
      '${b[p]}.${b[p+1]}.${b[p+2]}.${b[p+3]}';

  static bool _safeDomain(String x) =>
      x.isNotEmpty && x.length <= 253 &&
      RegExp(r'^[A-Za-z0-9_-]+(?:\.[A-Za-z0-9_-]+)*\.?$').hasMatch(x);

  static String? _dns(Uint8List b, int p, int e) {
    if (p+17 > e || b[p+4] != 0 || b[p+5] != 1) return null;
    var i = p+12;
    final labels = <String>[];
    for (var n=0; n<16; n++) {
      if (i >= e) return null;
      final len = b[i++];
      if (len == 0) {
        if (i+4 > e) return null;
        final name = labels.join('.');
        return _safeDomain(name) ? name : null;
      }
      if (len > 63 || i+len > e) return null;
      final label = latin1.decode(b.sublist(i, i+len));
      if (!_safeDomain(label)) return null;
      labels.add(label);
      i += len;
    }
    return null;
  }

  static String? _sni(Uint8List b, int p, int e) {
    if (p+44 > e || b[p] != 22 || b[p+1] != 3 || b[p+5] != 1) {
      return null;
    }
    final recordEnd = p+5+_u16(b,p+3,false);
    if (recordEnd > e) return null;
    var i=p+9+34;
    if (i>=recordEnd) return null;
    i+=1+b[i];
    if (i+2>recordEnd) return null;
    i+=2+_u16(b,i,false);
    if (i>=recordEnd) return null;
    i+=1+b[i];
    if (i+2>recordEnd) return null;
    final extEnd=i+2+_u16(b,i,false);
    i+=2;
    if (extEnd>recordEnd) return null;
    while (i+4<=extEnd) {
      final type=_u16(b,i,false), len=_u16(b,i+2,false);
      i+=4;
      if (i+len>extEnd) return null;
      if (type==0 && len>=5) {
        final listLen=_u16(b,i,false), hostLen=_u16(b,i+3,false);
        if (listLen+2>len || b[i+2]!=0 || hostLen+5>len) return null;
        final host=latin1.decode(b.sublist(i+5,i+5+hostLen));
        return _safeDomain(host) ? host : null;
      }
      i+=len;
    }
    return null;
  }

  static String? _header(String text,String field) {
    return RegExp('(?:^|\\r\\n)${RegExp.escape(field)}:[ \\t]*([^\\r\\n]+)',
       caseSensitive:false).firstMatch(text)?.group(1)?.trim();
  }

  static String? _preview(String body) {
    // Reject secrets rather than trying to mask every password format.
    if (RegExp(
      r'password|token|secret|api[_-]?key|authorization|cookie|session|credential|bearer|email|phone',
      caseSensitive:false,
    ).hasMatch(body)) return '[機微情報の可能性があるため非表示]';
    final text = body.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim();
    if (text.isEmpty) return null;
    return text.length > 120 ? '${text.substring(0,120)}…' : text;
  }

  static PcapObservation? _packet(
    Uint8List b, int begin, int end, int link, bool showBody,
  ) {
    var p=begin;
    if (link==1) {
      if (p+14>end) return null;
      var type=_u16(b,p+12,false);
      p+=14;
      for(var n=0;n<2 && (type==0x8100 || type==0x88a8);n++){
        if(p+4>end) return null;
        type=_u16(b,p+2,false);p+=4;
      }
      if(type!=0x0800)return null;
    }
    if(p+20>end || b[p]>>4!=4)return null;
    final h=(b[p]&15)*4;
    if(h<20 || p+h>end)return null;
    final ipEnd=(p+_u16(b,p+2,false)).clamp(p+h,end);
    if (_u16(b,p+6,false)&0x1fff!=0) return null;
    final src=_ip(b,p+12),dst=_ip(b,p+16);
    final proto=b[p+9];
    if(proto!=6 && proto!=17)return null;
    var q=p+h;
    if(q+8>ipEnd)return null;
    final sport=_u16(b,q,false),dport=_u16(b,q+2,false);
    if(proto==6){
      if(q+20>ipEnd)return null;
      final tcpHeader=(b[q+12]>>4)*4;
      if(tcpHeader<20||q+tcpHeader>ipEnd)return null;
      q+=tcpHeader;
    }else{
      final udpLen=_u16(b,q+4,false);
      if(udpLen<8||q+udpLen>ipEnd)return null;
      q+=8;
    }
    final transport=proto==6?'TCP':'UDP';
    var summary='\$transport 接続';
    String? host,body;
    var encrypted=false;
    if(proto==17 && (sport==53 || dport==53)){
      host=_dns(b,q,ipEnd);
      summary=host==null?'DNS（名前未解析）':'DNS問い合わせ（接続先の証明ではありません）';
    }else if(proto==6 && q<ipEnd){
      if(b[q]==22 && q+1<ipEnd && b[q+1]==3){
        host=_sni(b,q,ipEnd);
        summary=host==null?'TLS暗号化（本文は読めません）':
          'TLS ClientHello / SNI（自己申告のホスト）';
        encrypted=true;
      }else{
        final limit=(q+2048).clamp(q,ipEnd);
        final payload=latin1.decode(b.sublist(q,limit));
        final match=RegExp(
          r'^(GET|POST|PUT|HEAD|DELETE|PATCH|OPTIONS) ([^\r\n ]{1,512}) HTTP/1\.[01]\r\n',
        ).firstMatch(payload);
        if(match!=null){
          final method=match.group(1)!,path=match.group(2)!.split('?').first;
          final hostValue=_header(payload,'Host');
          host=hostValue!=null&&_safeDomain(hostValue)?hostValue:null;
          summary='平文HTTP \$method ${path.length>80?path.substring(0,80):path}';
          final mime=_header(payload,'Content-Type')?.toLowerCase();
          final bodyAt=payload.indexOf('\r\n\r\n');
          if(showBody && bodyAt>=0 &&
             (mime?.startsWith('text/plain')==true ||
              mime?.startsWith('application/json')==true)){
            body=_preview(payload.substring(bodyAt+4));
          }
        }else if(sport==443||dport==443){
          summary='TCP/443（HTTPSの可能性・本文は読めません）';
          encrypted=true;
        }
      }
    }else if(proto==17 && (sport==443||dport==443)){
      summary='UDP/443（QUICの可能性・本文は読めません）';
      encrypted=true;
    }
    return PcapObservation(sourceIp:src,destinationIp:dst,
      sourcePort:sport,destinationPort:dport,protocol:transport,
      description:summary,hostHint:host,plaintextPreview:body,
      encrypted:encrypted);
  }

  static PcapInspection parseBytes(Uint8List b,{bool includePlaintextBody=false}){
    if(b.length<24||b.length>maxFileBytes)
      throw const FormatException('PCAPは2MiB以下にしてください');
    final magic=b.sublist(0,4).join(',');
    final le=magic=='212,195,178,161'||magic=='77,60,178,161';
    if(!le && magic!='161,178,195,212' && magic!='161,178,60,77')
      throw const FormatException('classic PCAPのみ対応（PCAPNGは未対応）');
    if(_u16(b,4,le)!=2||_u16(b,6,le)!=4)
      throw const FormatException('PCAP 2.4以外は未対応');
    final link=_u32(b,20,le);
    if(link!=1&&link!=101)
      throw const FormatException('Ethernet/Raw IPv4 PCAPのみ対応');
    final rows=<PcapObservation>[];
    var total=0,p=24;
    while(p<b.length){
      if(p+16>b.length)throw const FormatException('PCAPヘッダー切れ');
      final length=_u32(b,p+8,le),orig=_u32(b,p+12,le);
      p+=16;
      if(length>65535||length>orig||p+length>b.length)
        throw const FormatException('PCAPレコード長が不正');
      total++;
      if(total>maxPacketCount)throw const FormatException('2500パケットを超えています');
      if(rows.length<maxVisible){
        final item=_packet(b,p,p+length,link,includePlaintextBody);
        if(item!=null)rows.add(item);
      }
      p+=length;
    }
    return PcapInspection._(
      total,total>maxVisible,includePlaintextBody,List.unmodifiable(rows));
  }
}
