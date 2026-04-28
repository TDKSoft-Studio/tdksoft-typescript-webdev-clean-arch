export abstract class AggregateRoot<T> {
  protected _id: string;
  protected props: T;
  private _domainEvents: any[] = [];

  constructor(props: T, id?: string) {
    this.props = props;
    this._id = id || Math.random().toString(36).substring(2, 9);
  }
}
