/**
 * 主题聚合服务
 * - 自定义文化主题（如"夏商文明"、"龙门造像"），将收藏的遗址/文物归类
 * - 提供主题卡片、节点网络数据、默认推荐主题
 */
import { UserDataService } from './UserDataService';
import { CultureService } from './CultureService';
import { Topic, TopicRelation, Site, Artifact } from '../model/entity/Entities';
import { FavoriteTargetType } from '../common/constants/Enums';
import { StringUtil } from '../common/utils/StringUtil';

const TAG = 'TopicService';

export interface TopicCardData {
  topic: Topic;
  siteCount: number;
  artifactCount: number;
  noteCount: number;
  sites: Site[];
  artifacts: Artifact[];
}

/** 知识图谱节点 */
export interface GraphNode {
  id: string;
  label: string;
  type: 'topic' | 'site' | 'artifact' | 'era';
  color: string;
  size: number;
}

type GraphNodeType = 'topic' | 'site' | 'artifact' | 'era';

export interface GraphEdge {
  source: string;
  target: string;
  label?: string;
}

export interface KnowledgeGraph {
  nodes: GraphNode[];
  edges: GraphEdge[];
}

export class TopicService {
  private static instance: TopicService;

  static getInstance(): TopicService {
    if (!TopicService.instance) {
      TopicService.instance = new TopicService();
    }
    return TopicService.instance;
  }

  /** 获取主题卡片列表（带聚合统计） */
  async getTopicCards(): Promise<TopicCardData[]> {
    const us = UserDataService.getInstance();
    const cs = CultureService.getInstance();
    await cs.warmCache();
    const topics = await us.listTopics();
    const notes = await us.listNotes();
    const cards: TopicCardData[] = [];
    for (const t of topics) {
      const rels = await us.listTopicRelations(t.id);
      const sites: Site[] = [];
      const artifacts: Artifact[] = [];
      for (const r of rels) {
        if (r.targetType === FavoriteTargetType.SITE) {
          const s = cs.getSiteByIdSync(r.targetId);
          if (s) sites.push(s);
        } else if (r.targetType === FavoriteTargetType.ARTIFACT) {
          const a = cs.getArtifactByIdSync(r.targetId);
          if (a) artifacts.push(a);
        }
      }
      // 统计笔记数
      const noteCount = notes.filter(n => {
        if (n.targetType === 'topic' && n.targetId === t.id) return true;
        // 与主题关联对象关联的笔记也算
        return sites.some(s => n.targetId === s.id) || artifacts.some(a => n.targetId === a.id);
      }).length;
      cards.push({
        topic: t,
        siteCount: sites.length,
        artifactCount: artifacts.length,
        noteCount,
        sites: sites.slice(0, 4),
        artifacts: artifacts.slice(0, 4),
      });
    }
    return cards;
  }

  /** 创建一个新主题 */
  async createTopic(name: string, description: string = '', iconEmoji: string = '📜', coverColor: string = '#C9A96E'): Promise<string> {
    return UserDataService.getInstance().createTopic(name, description, coverColor, iconEmoji);
  }

  /** 删除主题（软删除，关系保留但topic标记为删除） */
  async deleteTopic(topicId: string): Promise<void> {
    await UserDataService.getInstance().deleteTopic(topicId);
  }

  /** 把一个收藏加入主题 */
  async addToTopic(topicId: string, targetType: FavoriteTargetType, targetId: string): Promise<void> {
    await UserDataService.getInstance().addTopicRelation(topicId, targetType, targetId);
  }

  /** 生成个人知识图谱（主题为中心节点） */
  async buildKnowledgeGraph(): Promise<KnowledgeGraph> {
    const us = UserDataService.getInstance();
    const cs = CultureService.getInstance();
    await cs.warmCache();
    const nodes: GraphNode[] = [];
    const edges: GraphEdge[] = [];
    const added = new Set<string>();

    const addNode = (id: string, label: string, type: GraphNodeType, color: string, size: number = 1): void => {
      if (added.has(id)) return;
      added.add(id);
      nodes.push({ id, label, type, color, size });
    };

    const topics = await us.listTopics();
    for (const t of topics) {
      addNode(`topic:${t.id}`, t.name, 'topic', t.coverColor || '#C9A96E', 3);
      const rels = await us.listTopicRelations(t.id);
      const eras = new Set<string>();
      for (const r of rels) {
        if (r.targetType === FavoriteTargetType.SITE) {
          const s = cs.getSiteByIdSync(r.targetId);
          if (s) {
            addNode(`site:${s.id}`, s.name, 'site', '#8B6F47', 1.5);
            edges.push({ source: `topic:${t.id}`, target: `site:${s.id}`, label: '包含' });
            eras.add(s.era);
          }
        } else if (r.targetType === FavoriteTargetType.ARTIFACT) {
          const a = cs.getArtifactByIdSync(r.targetId);
          if (a) {
            addNode(`artifact:${a.id}`, a.name, 'artifact', '#A0522D', 1.2);
            edges.push({ source: `topic:${t.id}`, target: `artifact:${a.id}`, label: '藏有' });
            eras.add(a.era);
            // 文物所属遗址
            if (a.siteId) {
              const site = cs.getSiteByIdSync(a.siteId);
              if (site) {
                addNode(`site:${site.id}`, site.name, 'site', '#8B6F47', 1.5);
                edges.push({ source: `artifact:${a.id}`, target: `site:${site.id}`, label: '出土' });
              }
            }
          }
        }
      }
      // 时代标签作为抽象节点
      for (const era of eras) {
        addNode(`era:${era}`, era, 'era', '#5C6B73', 2);
        edges.push({ source: `topic:${t.id}`, target: `era:${era}`, label: '跨' });
      }
    }

    return { nodes, edges };
  }
}
