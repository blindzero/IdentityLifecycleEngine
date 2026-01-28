import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

const FeatureList = [
  {
    title: 'Workflow Oriented',
    Image: require('@site/static/assets/img/idle_feature_workflow-oriented.png').default,
    description: (
      <>
        Manage the lifecycle of identities seamlessly as they join, move within, or leave your organization.
      </>
    ),
  },
  {
    title: 'Provider Agnostic',
    Image: require('@site/static/assets/img/idle_feature_provider-agnostic.png').default,
    description: (
      <>
        Integrate with a wide range of identity providers and services, ensuring flexibility, adaptability and extensibility to your existing infrastructure.
      </>
    ),
  },
  {
    title: 'Built for Automation',
    Image: require('@site/static/assets/img/idle_feature_built-for-automation.png').default,
    description: (
      <>
        Designed to automate identity management tasks, reducing manual effort and minimizing errors.
      </>
    ),
  },
];

function Feature({Image, title, description}) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <img className={styles.featureImg} src={Image} alt={title} />
      </div>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
